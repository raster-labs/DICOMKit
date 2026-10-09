// NEMA-verified: 2026a, checked 2026-09-29 — Hanging Protocol Level (MANUFACTURER, SITE, USER_GROUP, SINGLE_USER) per PS3.3 2026a Table C.23.1-1; Partial Data Display Handling top-level Type 2 per Table C.23.3-1; Screen Specifications per Table C.23.2-2; Synchronized Scrolling Sequence (0072,0210) and Navigation Indicator Sequence (0072,0214) top-level Type 3 per Table C.23.3-1; Image Set Number resolution per Table C.23.3-1 (Display Sets item refers to a Time Based Image Sets item)
//
// HangingProtocol.swift
// DICOMKit
//
// Created by DICOMKit on 2026-02-05.
// Copyright © 2026 DICOMKit. All rights reserved.
//

import Foundation
import DICOMCore

/// Hanging Protocol Information Object Definition (IOD)
///
/// Hanging Protocols define how studies should be displayed on viewing workstations,
/// including layout, image selection, and display parameters.
///
/// Reference: PS3.3 Section A.38 - Hanging Protocol IOD
/// Reference: PS3.3 Section C.23 - Hanging Protocol Modules
public struct HangingProtocol: Sendable {
    // MARK: - Identification
    
    /// Unique name for the hanging protocol
    public let name: String
    
    /// Human-readable description of the protocol
    public let description: String?
    
    /// Hanging Protocol Level (0072,0006)
    public let level: HangingProtocolLevel
    
    /// Creator of the protocol
    public let creator: String?
    
    /// Creation date and time
    public let creationDateTime: DICOMDateTime?
    
    /// Number of prior studies referenced
    public let numberOfPriorsReferenced: Int?
    
    // MARK: - Environment
    
    /// Environments (modality, laterality combinations) where this protocol applies
    public let environments: [HangingProtocolEnvironment]
    
    // MARK: - User Identification
    
    /// User groups or individuals this protocol applies to
    public let userGroups: [String]
    
    // MARK: - Image Sets
    
    /// Image sets defined by this protocol
    public let imageSets: [ImageSetDefinition]
    
    // MARK: - Display Specification
    
    /// Number of screens used
    public let numberOfScreens: Int
    
    /// Screen definitions for nominal display configuration
    public let screenDefinitions: [ScreenDefinition]
    
    /// Display sets specifying how images should be arranged
    public let displaySets: [DisplaySet]

    /// Partial Data Display Handling (0072,0208), Type 2: whether to keep
    /// the layout when an image set is not available. `nil` is written as
    /// zero length, meaning the behaviour is not defined (PS3.3 Table C.23.3-1).
    public let partialDataDisplayHandling: PartialDataDisplayHandling?

    /// Synchronized Scrolling Sequence (0072,0210), Type 3: top level of the
    /// Hanging Protocol Display Module (PS3.3 Table C.23.3-1). When empty,
    /// display sets sharing a deprecated `DisplaySet.scrollingGroup` value
    /// are written as one item each.
    public let synchronizedScrolling: [SynchronizedScrollingGroup]

    /// Navigation Indicator Sequence (0072,0214), Type 3: top level of the
    /// Hanging Protocol Display Module (PS3.3 Table C.23.3-1)
    public let navigationIndicators: [NavigationIndicator]

    // MARK: - Initialization

    public init(
        name: String,
        description: String? = nil,
        level: HangingProtocolLevel = .user,
        creator: String? = nil,
        creationDateTime: DICOMDateTime? = nil,
        numberOfPriorsReferenced: Int? = nil,
        environments: [HangingProtocolEnvironment] = [],
        userGroups: [String] = [],
        imageSets: [ImageSetDefinition] = [],
        numberOfScreens: Int = 1,
        screenDefinitions: [ScreenDefinition] = [],
        displaySets: [DisplaySet] = [],
        partialDataDisplayHandling: PartialDataDisplayHandling? = nil,
        synchronizedScrolling: [SynchronizedScrollingGroup] = [],
        navigationIndicators: [NavigationIndicator] = []
    ) {
        self.name = name
        self.description = description
        self.level = level
        self.creator = creator
        self.creationDateTime = creationDateTime
        self.numberOfPriorsReferenced = numberOfPriorsReferenced
        self.environments = environments
        self.userGroups = userGroups
        self.imageSets = imageSets
        self.numberOfScreens = numberOfScreens
        self.screenDefinitions = screenDefinitions
        self.displaySets = displaySets
        self.partialDataDisplayHandling = partialDataDisplayHandling
        self.synchronizedScrolling = synchronizedScrolling
        self.navigationIndicators = navigationIndicators
    }

    /// Every Image Set Number (0072,0032) defined by the Time Based Image
    /// Sets Sequence items of all image sets.
    public var imageSetNumbers: [Int] { imageSets.flatMap(\.imageSetNumbers) }

    /// The Image Set Number (0072,0032) a display set shows: its own, else
    /// the first of the deprecated `ImageBox.imageSetNumbers`, else the only
    /// image set number when the protocol defines exactly one.
    public func resolvedImageSetNumber(for displaySet: DisplaySet) -> Int? {
        if let number = displaySet.imageSetNumber { return number }
        if let legacy = displaySet.imageBoxes.lazy.flatMap(\.legacyImageSetNumbers).first { return legacy }
        let all = imageSetNumbers
        return all.count == 1 ? all[0] : nil
    }

}

// MARK: - Hanging Protocol Level

/// Hanging Protocol Level (0072,0006)
///
/// PS3.3 Table C.23.1-1 Enumerated Values: MANUFACTURER, SITE, USER_GROUP,
/// SINGLE_USER.
public enum HangingProtocolLevel: String, Sendable, Codable, CaseIterable {
    /// Manufacturer-level protocol (shipped with the application)
    case manufacturer = "MANUFACTURER"

    /// Site-level protocol (applies to entire institution)
    case site = "SITE"
    
    /// Group-level protocol (applies to department or group)
    case group = "USER_GROUP"

    /// User-level protocol (applies to individual user)
    case user = "SINGLE_USER"
}

// MARK: - Hanging Protocol Environment

/// Environment specification for protocol matching
///
/// Defines the clinical context where a hanging protocol should be applied,
/// such as modality and anatomic laterality.
public struct HangingProtocolEnvironment: Sendable {
    /// Modality (e.g., "CT", "MR", "CR", "DX")
    public let modality: String?
    
    /// Anatomic laterality (e.g., "L", "R")
    public let laterality: String?
    
    public init(modality: String? = nil, laterality: String? = nil) {
        self.modality = modality
        self.laterality = laterality
    }
}

// MARK: - Screen Definition

/// Nominal screen definition for multi-monitor configurations
public struct ScreenDefinition: Sendable {
    /// Number of vertical pixels
    public let verticalPixels: Int
    
    /// Number of horizontal pixels
    public let horizontalPixels: Int
    
    /// Spatial position in multi-monitor setup (1-based)
    public let spatialPosition: [Double]?
    
    /// Minimum grayscale bit depth
    public let minimumGrayscaleBitDepth: Int?
    
    /// Minimum color bit depth
    public let minimumColorBitDepth: Int?
    
    /// Maximum application repaint time in milliseconds
    public let maximumRepaintTime: Int?
    
    public init(
        verticalPixels: Int,
        horizontalPixels: Int,
        spatialPosition: [Double]? = nil,
        minimumGrayscaleBitDepth: Int? = nil,
        minimumColorBitDepth: Int? = nil,
        maximumRepaintTime: Int? = nil
    ) {
        self.verticalPixels = verticalPixels
        self.horizontalPixels = horizontalPixels
        self.spatialPosition = spatialPosition
        self.minimumGrayscaleBitDepth = minimumGrayscaleBitDepth
        self.minimumColorBitDepth = minimumColorBitDepth
        self.maximumRepaintTime = maximumRepaintTime
    }
}
