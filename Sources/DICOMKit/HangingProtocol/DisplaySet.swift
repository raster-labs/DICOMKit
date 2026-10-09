// NEMA-verified: 2026a, checked 2026-09-29 — Image Box Layout Type, Scroll Direction, Small/Large Scroll Type, Reformatting Operation Type, Initial View Direction, 3D Rendering Type, Partial Data Display Handling, VOI Type, Horizontal/Vertical Justification and the YES/NO flags against PS3.3 2026a Table C.23.3-1; item nesting per Table C.23.3-1 (Image Set Number, Filter/Sorting Operations, Blending Operation Type COLOR, Reformatting 0072,0510-0516 and 3D Rendering Type at Display Sets item level; Display Environment Spatial Position FD VM 4, Preferred Playback Sequencing US 0/1/2, Recommended Display Frame Rate IS in Image Boxes items; Synchronized Scrolling US 2-n and Navigation Indicator 0072,0216/0218 US at top level), VRs per PS3.6 2026a Table 6-1
//
// DisplaySet.swift
// DICOMKit
//
// Created by DICOMKit on 2026-02-05.
// Copyright © 2026 DICOMKit. All rights reserved.
//

import Foundation
import DICOMCore

/// Display Set specification for Hanging Protocol
///
/// One item of the Display Sets Sequence (0072,0200), PS3.3 Table C.23.3-1.
/// The item's operations apply to the image set named by `imageSetNumber` in
/// the order Filter Operations, Reformatting, Sorting Operations,
/// Presentation Intent (PS3.3 C.23.3.1).
///
/// Reference: PS3.3 Table C.23.3-1 - Display Sets Sequence (0072,0200)
public struct DisplaySet: Sendable {
    /// Display Set Number (0072,0202), 1-based
    public let number: Int

    /// Display Set Label (0072,0203)
    public let label: String?

    /// Display Set Presentation Group (0072,0204)
    public let presentationGroup: Int?

    /// Display Set Presentation Group Description (0072,0206)
    public let presentationGroupDescription: String?

    /// Image Set Number (0072,0032), Type 1: the Time Based Image Sets
    /// Sequence (0072,0030) item whose image set this display set shows.
    /// When nil, the first of the deprecated `ImageBox.imageSetNumbers` is
    /// written, or the only image set number when the protocol defines one.
    public let imageSetNumber: Int?

    /// Filter Operations Sequence (0072,0400), Type 2 (written empty when
    /// there are none)
    public let filterOperations: [FilterOperation]

    /// Sorting Operations Sequence (0072,0600), Type 2 (written empty when
    /// there are none)
    public let sortingOperations: [SortOperation]

    /// Blending Operation Type (0072,0500), Type 3
    public let blendingOperationType: BlendingOperationType?

    /// Reformatting Operation Type, Thickness, Interval and Initial View
    /// Direction (0072,0510 - 0516)
    public let reformattingOperation: ReformattingOperation?

    /// 3D Rendering Type (0072,0520) Value 1, Type 1C for 3D_RENDERING
    public let threeDRenderingType: ThreeDRenderingType?

    /// 3D Rendering Type (0072,0520) values 2..n: implementation specific
    /// sub-types (PS3.3 Table C.23.3-1)
    public let threeDRenderingSubtypes: [String]

    /// Partial Data Display Handling (0072,0208) is a top-level attribute of
    /// the Hanging Protocol Display Module (PS3.3 Table C.23.3-1), see
    /// `HangingProtocol.partialDataDisplayHandling`. A value here is not
    /// written; the serializer promotes it to the top level when the
    /// protocol has none and it is a `PartialDataDisplayHandling` term.
    @available(*, deprecated, message: "Partial Data Display Handling (0072,0208) is a top-level Type 2 attribute in PS3.3 2026a Table C.23.3-1; use HangingProtocol.partialDataDisplayHandling")
    public let partialDataHandling: String?

    /// Scrolling group given through the deprecated API.
    let legacyScrollingGroup: Int?

    /// Scrolling group identifier for synchronized scrolling. Display Set
    /// Scrolling Group (0072,0212) is a list of Display Set Numbers in a
    /// Synchronized Scrolling Sequence (0072,0210) item at the top level of
    /// the module (PS3.3 Table C.23.3-1); display sets sharing a value here
    /// are written as one such item when `HangingProtocol.synchronizedScrolling`
    /// is empty. A parsed display set reports the 1-based index of the first
    /// Synchronized Scrolling Sequence item that lists it.
    @available(*, deprecated, message: "Display Set Scrolling Group (0072,0212) lists Display Set Numbers in a Synchronized Scrolling Sequence (0072,0210) item in PS3.3 2026a Table C.23.3-1; use HangingProtocol.synchronizedScrolling")
    public var scrollingGroup: Int? { legacyScrollingGroup }

    /// Image boxes defining the layout
    public let imageBoxes: [ImageBox]

    /// Display options
    public let displayOptions: DisplayOptions

    public init(
        number: Int,
        label: String? = nil,
        presentationGroup: Int? = nil,
        presentationGroupDescription: String? = nil,
        partialDataHandling: String? = nil,
        scrollingGroup: Int? = nil,
        imageSetNumber: Int? = nil,
        imageBoxes: [ImageBox] = [],
        filterOperations: [FilterOperation] = [],
        sortingOperations: [SortOperation] = [],
        blendingOperationType: BlendingOperationType? = nil,
        reformattingOperation: ReformattingOperation? = nil,
        threeDRenderingType: ThreeDRenderingType? = nil,
        threeDRenderingSubtypes: [String] = [],
        displayOptions: DisplayOptions = DisplayOptions()
    ) {
        self.number = number
        self.label = label
        self.presentationGroup = presentationGroup
        self.presentationGroupDescription = presentationGroupDescription
        self.partialDataHandling = partialDataHandling
        self.legacyScrollingGroup = scrollingGroup
        self.imageSetNumber = imageSetNumber
        self.imageBoxes = imageBoxes
        self.filterOperations = filterOperations
        self.sortingOperations = sortingOperations
        self.blendingOperationType = blendingOperationType
        self.reformattingOperation = reformattingOperation
        self.threeDRenderingType = threeDRenderingType
        self.threeDRenderingSubtypes = threeDRenderingSubtypes
        self.displayOptions = displayOptions
    }

    /// A copy with the deprecated scrolling group set.
    func replacing(legacyScrollingGroup group: Int?) -> DisplaySet {
        DisplaySet(
            number: number,
            label: label,
            presentationGroup: presentationGroup,
            presentationGroupDescription: presentationGroupDescription,
            scrollingGroup: group,
            imageSetNumber: imageSetNumber,
            imageBoxes: imageBoxes,
            filterOperations: filterOperations,
            sortingOperations: sortingOperations,
            blendingOperationType: blendingOperationType,
            reformattingOperation: reformattingOperation,
            threeDRenderingType: threeDRenderingType,
            threeDRenderingSubtypes: threeDRenderingSubtypes,
            displayOptions: displayOptions
        )
    }

    /// Reformatting operation written for this display set: its own, else
    /// the first one given through the deprecated `ImageBox` API.
    var effectiveReformattingOperation: ReformattingOperation? {
        reformattingOperation ?? imageBoxes.lazy.compactMap(\.legacyReformattingOperation).first
    }

    /// 3D Rendering Type (0072,0520) values written for this display set:
    /// its own, else the first image box's (deprecated API), else those a
    /// deprecated projection `ReformattingType` implies.
    var effectiveThreeDRenderingValues: [String] {
        if let threeDRenderingType {
            return [threeDRenderingType.rawValue] + threeDRenderingSubtypes
        }
        if reformattingOperation == nil,
           let box = imageBoxes.first(where: { $0.legacyThreeDRenderingType != nil }),
           let type = box.legacyThreeDRenderingType {
            return [type.rawValue] + box.legacyThreeDRenderingSubtypes
        }
        if let implied = effectiveReformattingOperation?.type.impliedRenderingType {
            return [implied.type.rawValue] + implied.subtypes
        }
        return []
    }
}

// MARK: - Blending Operation Type

/// Blending Operation Type (0072,0500)
///
/// PS3.3 Table C.23.3-1 Defined Terms; see C.23.3.1.3.
public enum BlendingOperationType: String, Sendable, Codable, CaseIterable {
    /// Apply a pseudo-color to the superimposed image while blending
    case color = "COLOR"
}

// MARK: - Synchronized Scrolling

/// One item of the Synchronized Scrolling Sequence (0072,0210), PS3.3
/// Table C.23.3-1: display sets scrolled in parallel along the dimensions of
/// their Sorting Operations Sequence (0072,0600).
public struct SynchronizedScrollingGroup: Sendable, Equatable {
    /// Display Set Scrolling Group (0072,0212), US VM 2-n: two or more
    /// Display Set Number (0072,0202) values
    public let displaySetNumbers: [Int]

    public init(displaySetNumbers: [Int]) {
        self.displaySetNumbers = displaySetNumbers
    }
}

// MARK: - Navigation Indicator

/// One item of the Navigation Indicator Sequence (0072,0214), PS3.3 Table
/// C.23.3-1: a geometric relationship between display sets for localization
/// or navigation.
public struct NavigationIndicator: Sendable, Equatable {
    /// Navigation Display Set (0072,0216), US, Type 1C: the display set on
    /// which the Reference Display Sets are depicted or controlled; nil when
    /// the reference display sets cross-reference each other
    public let navigationDisplaySet: Int?

    /// Reference Display Sets (0072,0218), US VM 1-n, Type 1
    public let referenceDisplaySets: [Int]

    public init(navigationDisplaySet: Int? = nil, referenceDisplaySets: [Int]) {
        self.navigationDisplaySet = navigationDisplaySet
        self.referenceDisplaySets = referenceDisplaySets
    }
}

/// Partial Data Display Handling (0072,0208)
///
/// PS3.3 Table C.23.3-1 Enumerated Values.
public enum PartialDataDisplayHandling: String, Sendable, Codable {
    /// If one or more Image Sets is not available, maintain the layout with empty Image Boxes
    case maintainLayout = "MAINTAIN_LAYOUT"

    /// If one or more Image Sets is not available, rearrange the layout at the discretion of the application
    case adaptLayout = "ADAPT_LAYOUT"
}

// MARK: - Image Box

/// Image box within a display set
///
/// One item of the Image Boxes Sequence (0072,0300).
public struct ImageBox: Sendable {
    /// Image Box Number (0072,0302), 1-based
    public let number: Int

    /// Image Box Layout Type (0072,0304)
    public let layoutType: ImageBoxLayoutType

    /// Image set numbers given through the deprecated API.
    let legacyImageSetNumbers: [Int]

    /// References to image sets to display in this box. PS3.3 Table
    /// C.23.3-1 has no image set reference in an Image Boxes Sequence item:
    /// the display set names one image set in Image Set Number (0072,0032).
    /// The first value here is written there when `DisplaySet.imageSetNumber`
    /// is nil.
    @available(*, deprecated, message: "Image Set Number (0072,0032) is a Display Sets Sequence (0072,0200) item attribute in PS3.3 2026a Table C.23.3-1; use DisplaySet.imageSetNumber")
    public var imageSetNumbers: [Int] { legacyImageSetNumbers }

    /// Display Environment Spatial Position (0072,0108), FD VM 4, Type 1 in
    /// an Image Boxes Sequence item (PS3.3 Table C.23.3-1): the box's
    /// rectangle within the bounding box of all the display space
    public let displayEnvironmentSpatialPosition: [Double]?

    /// Image Box Tile Horizontal / Vertical Dimension (0072,0306 / 0308),
    /// required for TILED
    public let tileHorizontalDimension: Int?
    public let tileVerticalDimension: Int?

    /// Scroll settings (0072,0310 - 0318)
    public let scrollDirection: ScrollDirection?
    public let smallScrollType: ScrollType?
    public let smallScrollAmount: Int?
    public let largeScrollType: ScrollType?
    public let largeScrollAmount: Int?

    /// Image Box Overlap Priority (0072,0320): 1 = top ... 100 = bottom
    public let overlapPriority: Int?

    /// Preferred Playback Sequencing (0018,1244), US, Type 1C: required if
    /// the layout type is CINE; overrides the value in the images
    public let preferredPlaybackSequencing: PreferredPlaybackSequencing?

    /// Recommended Display Frame Rate (0008,2144), IS, Type 1C: frames per
    /// second, required for CINE when Cine Relative to Real-Time is absent
    public let recommendedDisplayFrameRate: Int?

    /// Cine Relative to Real-Time (0072,0330)
    public let cineRelativeToRealTime: Double?

    /// Synchronization settings
    public let synchronizationGroup: Int?

    /// Reformatting / 3D rendering given through the deprecated API.
    let legacyReformattingOperation: ReformattingOperation?
    let legacyThreeDRenderingType: ThreeDRenderingType?
    let legacyThreeDRenderingSubtypes: [String]

    /// Reformatting operation (0072,0510 - 0516). These are Display Sets
    /// Sequence item attributes (PS3.3 Table C.23.3-1); a value here is
    /// written at display set level when the display set has none.
    @available(*, deprecated, message: "Reformatting Operation Type and its attributes are Display Sets Sequence (0072,0200) item attributes in PS3.3 2026a Table C.23.3-1; use DisplaySet.reformattingOperation")
    public var reformattingOperation: ReformattingOperation? { legacyReformattingOperation }

    /// 3D Rendering Type (0072,0520) Value 1; a display set attribute (PS3.3
    /// Table C.23.3-1) written at display set level when the display set has none.
    @available(*, deprecated, message: "3D Rendering Type (0072,0520) is a Display Sets Sequence (0072,0200) item attribute in PS3.3 2026a Table C.23.3-1; use DisplaySet.threeDRenderingType")
    public var threeDRenderingType: ThreeDRenderingType? { legacyThreeDRenderingType }

    /// 3D Rendering Type (0072,0520) values 2..n: implementation specific
    /// sub-types (PS3.3 Table C.23.3-1)
    @available(*, deprecated, message: "3D Rendering Type (0072,0520) is a Display Sets Sequence (0072,0200) item attribute in PS3.3 2026a Table C.23.3-1; use DisplaySet.threeDRenderingSubtypes")
    public var threeDRenderingSubtypes: [String] { legacyThreeDRenderingSubtypes }

    public init(
        number: Int,
        layoutType: ImageBoxLayoutType = .stack,
        imageSetNumbers: [Int] = [],
        displayEnvironmentSpatialPosition: [Double]? = nil,
        tileHorizontalDimension: Int? = nil,
        tileVerticalDimension: Int? = nil,
        scrollDirection: ScrollDirection? = nil,
        smallScrollType: ScrollType? = nil,
        smallScrollAmount: Int? = nil,
        largeScrollType: ScrollType? = nil,
        largeScrollAmount: Int? = nil,
        overlapPriority: Int? = nil,
        preferredPlaybackSequencing: PreferredPlaybackSequencing? = nil,
        recommendedDisplayFrameRate: Int? = nil,
        cineRelativeToRealTime: Double? = nil,
        synchronizationGroup: Int? = nil,
        reformattingOperation: ReformattingOperation? = nil,
        threeDRenderingType: ThreeDRenderingType? = nil,
        threeDRenderingSubtypes: [String] = []
    ) {
        self.number = number
        self.layoutType = layoutType
        self.legacyImageSetNumbers = imageSetNumbers
        self.displayEnvironmentSpatialPosition = displayEnvironmentSpatialPosition
        self.tileHorizontalDimension = tileHorizontalDimension
        self.tileVerticalDimension = tileVerticalDimension
        self.scrollDirection = scrollDirection
        self.smallScrollType = smallScrollType
        self.smallScrollAmount = smallScrollAmount
        self.largeScrollType = largeScrollType
        self.largeScrollAmount = largeScrollAmount
        self.overlapPriority = overlapPriority
        self.preferredPlaybackSequencing = preferredPlaybackSequencing
        self.recommendedDisplayFrameRate = recommendedDisplayFrameRate
        self.cineRelativeToRealTime = cineRelativeToRealTime
        self.synchronizationGroup = synchronizationGroup
        self.legacyReformattingOperation = reformattingOperation
        self.legacyThreeDRenderingType = threeDRenderingType
        self.legacyThreeDRenderingSubtypes = threeDRenderingSubtypes
    }
}

// MARK: - Preferred Playback Sequencing

/// Preferred Playback Sequencing (0018,1244) of an Image Boxes Sequence item
///
/// PS3.3 Table C.23.3-1 Enumerated Values (US). The image box adds Stop (2)
/// to the Looping / Sweeping of the Cine Module (Table C.7-13).
public enum PreferredPlaybackSequencing: UInt16, Sendable, Codable, CaseIterable {
    /// Looping (1,2…n,1,2,…n,1,2,….n,…)
    case looping = 0

    /// Sweeping (1,2,…n,n-1,…2,1,2,…n,…)
    case sweeping = 1

    /// Stop (1,2…n)
    case stop = 2
}

// MARK: - Image Box Layout Type

/// Image Box Layout Type (0072,0304)
///
/// PS3.3 Table C.23.3-1 Defined Terms. All types except TILED are single
/// rectangles containing a single frame.
public enum ImageBoxLayoutType: String, Sendable, Codable {
    /// A scrollable array of rectangles, each containing a single frame
    case tiled = "TILED"

    /// A single rectangle containing a steppable single frame, for
    /// user-controlled stepping through the image set
    case stack = "STACK"

    /// A single rectangle for video type play back
    case cine = "CINE"

    /// Interactive 3D visualizations that have custom interfaces
    case processed = "PROCESSED"

    /// A single rectangle for images and objects with no defined methods of
    /// interaction; also for non-image objects such as waveforms and SR
    case single = "SINGLE"

    /// Not a term; serialised as TILED.
    @available(*, deprecated, renamed: "tiled", message: "TILED_ALL is not an Image Box Layout Type (0072,0304) term in PS3.3 2026a Table C.23.3-1")
    case tiledAll = "TILED_ALL"

    /// The Table C.23.3-1 term written for this case.
    var standardTerm: ImageBoxLayoutType {
        self == .tiledAll ? .tiled : self
    }

    /// Reads a layout type, mapping the old DICOMKit spelling.
    static func reading(_ raw: String) -> ImageBoxLayoutType? {
        let term = raw.trimmingCharacters(in: .whitespaces)
        return term == "TILED_ALL" ? .tiled : ImageBoxLayoutType(rawValue: term)
    }
}

// MARK: - Scroll Direction

/// Image Box Scroll Direction (0072,0310)
///
/// PS3.3 Table C.23.3-1 Enumerated Values.
public enum ScrollDirection: String, Sendable, Codable {
    /// Scroll images by column
    case horizontal = "HORIZONTAL"

    /// Scroll images by row
    case vertical = "VERTICAL"
}

// MARK: - Scroll Type

/// Image Box Small / Large Scroll Type (0072,0312 / 0072,0316)
///
/// PS3.3 Table C.23.3-1 Enumerated Values.
public enum ScrollType: String, Sendable, Codable {
    /// Replace all image slots with the next N x M images in the set
    case page = "PAGE"

    /// Move each row or column of images to the next row or column,
    /// depending on Image Box Scroll Direction
    case rowColumn = "ROW_COLUMN"

    /// Move each image to the next slot, horizontally or vertically,
    /// depending on Image Box Scroll Direction
    case image = "IMAGE"

    /// Not a term; serialised as PAGE.
    @available(*, deprecated, message: "FRACTION is not a Scroll Type (0072,0312 / 0072,0316) term in PS3.3 2026a Table C.23.3-1; use page, rowColumn or image")
    case fraction = "FRACTION"

    /// The Table C.23.3-1 term written for this case.
    var standardTerm: ScrollType {
        self == .fraction ? .page : self
    }

    /// Reads a scroll type, mapping the old DICOMKit spelling.
    static func reading(_ raw: String) -> ScrollType? {
        let term = raw.trimmingCharacters(in: .whitespaces)
        return term == "FRACTION" ? .page : ScrollType(rawValue: term)
    }
}

// MARK: - Reformatting Operation

/// Reformatting operation specification (0072,0510 - 0516)
public struct ReformattingOperation: Sendable {
    /// Reformatting Operation Type (0072,0510)
    public let type: ReformattingType

    /// Reformatting Thickness (0072,0512) in mm; required for SLAB or MPR
    public let thickness: Double?

    /// Reformatting Interval (0072,0514) in mm; required for SLAB or MPR
    public let interval: Double?

    /// Reformatting Operation Initial View Direction (0072,0516); required
    /// for MPR or 3D_RENDERING
    public let initialViewPlane: ImagePlane?

    public init(
        type: ReformattingType,
        thickness: Double? = nil,
        interval: Double? = nil,
        initialViewPlane: ImagePlane? = nil
    ) {
        self.type = type
        self.thickness = thickness
        self.interval = interval
        self.initialViewPlane = initialViewPlane
    }

    /// `initialViewDirection` must be an `ImagePlane` term ("AXIAL" is
    /// accepted as TRANSVERSE); other text is dropped.
    @available(*, deprecated, message: "Reformatting Operation Initial View Direction (0072,0516) takes the Defined Terms SAGITTAL, TRANSVERSE, CORONAL, OBLIQUE (PS3.3 2026a Table C.23.3-1); use init(type:thickness:interval:initialViewPlane:)")
    public init(
        type: ReformattingType,
        thickness: Double? = nil,
        interval: Double? = nil,
        initialViewDirection: String
    ) {
        self.type = type
        self.thickness = thickness
        self.interval = interval
        self.initialViewPlane = ImagePlane.reading(initialViewDirection)
    }

    /// `initialViewPlane` as its term.
    @available(*, deprecated, renamed: "initialViewPlane")
    public var initialViewDirection: String? { initialViewPlane?.rawValue }
}

/// Reformatting Operation Type (0072,0510)
///
/// PS3.3 Table C.23.3-1 Defined Terms.
public enum ReformattingType: String, Sendable, Codable {
    /// Multiplanar reformatting
    case mpr = "MPR"

    /// 3D rendering; the kind is given by 3D Rendering Type (0072,0520)
    case threeDRendering = "3D_RENDERING"

    /// Slab
    case slab = "SLAB"

    /// Not a term; serialised as MPR.
    @available(*, deprecated, message: "CPR is not a Reformatting Operation Type (0072,0510) term in PS3.3 2026a Table C.23.3-1; use mpr")
    case cpr = "CPR"

    /// Not a term; serialised as 3D_RENDERING with 3D Rendering Type MIP.
    @available(*, deprecated, message: "MIP is a 3D Rendering Type (0072,0520) term, not a Reformatting Operation Type (0072,0510); use threeDRendering with ImageBox.threeDRenderingType = .mip")
    case mip = "MIP"

    /// Not a term; serialised as 3D_RENDERING with 3D Rendering Type
    /// VOLUME\MINIP (Value 1 a Defined Term, Value 2 an implementation
    /// specific sub-type, PS3.3 Table C.23.3-1).
    @available(*, deprecated, message: "MinIP is not a Reformatting Operation Type (0072,0510) term in PS3.3 2026a Table C.23.3-1; use threeDRendering with ImageBox.threeDRenderingType / threeDRenderingSubtypes")
    case minIP = "MinIP"

    /// Not a term; serialised as 3D_RENDERING with 3D Rendering Type
    /// VOLUME\AVGIP (Value 1 a Defined Term, Value 2 an implementation
    /// specific sub-type, PS3.3 Table C.23.3-1).
    @available(*, deprecated, message: "AvgIP is not a Reformatting Operation Type (0072,0510) term in PS3.3 2026a Table C.23.3-1; use threeDRendering with ImageBox.threeDRenderingType / threeDRenderingSubtypes")
    case avgIP = "AvgIP"

    /// The Table C.23.3-1 term written for this case.
    var standardTerm: ReformattingType {
        switch self {
        case .mpr, .threeDRendering, .slab: return self
        case .cpr: return .mpr
        case .mip, .minIP, .avgIP: return .threeDRendering
        }
    }

    /// The 3D Rendering Type (0072,0520) values a deprecated projection
    /// case implies when the image box states none.
    var impliedRenderingType: (type: ThreeDRenderingType, subtypes: [String])? {
        switch self {
        case .mip: return (.mip, [])
        case .minIP: return (.volumeRendering, ["MINIP"])
        case .avgIP: return (.volumeRendering, ["AVGIP"])
        default: return nil
        }
    }

    /// Reads a reformatting type, mapping the old DICOMKit spellings.
    static func reading(_ raw: String) -> ReformattingType? {
        let term = raw.trimmingCharacters(in: .whitespaces)
        switch term {
        case "CPR": return .mpr
        case "MIP", "MinIP", "AvgIP": return .threeDRendering
        default: return ReformattingType(rawValue: term)
        }
    }
}

/// 3D Rendering Type (0072,0520), Value 1
///
/// PS3.3 Table C.23.3-1 Defined Terms for Value 1; additional values are
/// implementation specific sub-types (`ImageBox.threeDRenderingSubtypes`).
public enum ThreeDRenderingType: String, Sendable, Codable {
    /// Volume rendering
    case volumeRendering = "VOLUME"

    /// Surface rendering
    case surfaceRendering = "SURFACE"

    /// Maximum intensity projection
    case mip = "MIP"
}

// MARK: - Display Options

/// Presentation intent attributes of a display set (PS3.3 C.23.3.1.4)
public struct DisplayOptions: Sendable {
    /// Display Set Patient Orientation (0072,0700): two values, the patient
    /// direction at the right side and at the bottom of the image box
    public let patientOrientation: String?

    /// VOI Type (0072,0702); `VOIType` lists the Defined Terms
    public let voiType: String?

    /// Pseudo-Color Type (0072,0704); the Defined Terms are the Content
    /// Labels of the PS3.6 Well-Known Color Palettes
    public let pseudoColorType: String?

    /// Show Grayscale Inverted (0072,0706) YES / NO
    public let showGrayscaleInverted: Bool

    /// Show Image True Size Flag (0072,0710) YES / NO
    public let showImageTrueSize: Bool

    /// Show Graphic Annotation Flag (0072,0712) YES / NO
    public let showGraphicAnnotations: Bool

    /// Show Patient Demographics Flag (0072,0714) YES / NO
    public let showPatientDemographics: Bool

    /// Show Acquisition Techniques Flag (0072,0716) YES / NO
    public let showAcquisitionTechniques: Bool

    /// Display Set Horizontal Justification (0072,0717): LEFT, CENTER, RIGHT
    public let horizontalJustification: Justification?

    /// Display Set Vertical Justification (0072,0718): TOP, CENTER, BOTTOM
    public let verticalJustification: Justification?

    public init(
        patientOrientation: String? = nil,
        voiType: String? = nil,
        pseudoColorType: String? = nil,
        showGrayscaleInverted: Bool = false,
        showImageTrueSize: Bool = false,
        showGraphicAnnotations: Bool = true,
        showPatientDemographics: Bool = true,
        showAcquisitionTechniques: Bool = true,
        horizontalJustification: Justification? = nil,
        verticalJustification: Justification? = nil
    ) {
        self.patientOrientation = patientOrientation
        self.voiType = voiType
        self.pseudoColorType = pseudoColorType
        self.showGrayscaleInverted = showGrayscaleInverted
        self.showImageTrueSize = showImageTrueSize
        self.showGraphicAnnotations = showGraphicAnnotations
        self.showPatientDemographics = showPatientDemographics
        self.showAcquisitionTechniques = showAcquisitionTechniques
        self.horizontalJustification = horizontalJustification
        self.verticalJustification = verticalJustification
    }

    /// `voiType` as a `VOIType` Defined Term, or nil for another value.
    public var voiTypeTerm: VOIType? {
        voiType.flatMap { VOIType(rawValue: $0.trimmingCharacters(in: .whitespaces)) }
    }
}

/// VOI Type (0072,0702)
///
/// PS3.3 Table C.23.3-1 Defined Terms.
public enum VOIType: String, Sendable, Codable, CaseIterable {
    case lung = "LUNG"
    case mediastinum = "MEDIASTINUM"
    case abdomenPelvis = "ABDO_PELVIS"
    case liver = "LIVER"
    case softTissue = "SOFT_TISSUE"
    case bone = "BONE"
    case brain = "BRAIN"
    case posteriorFossa = "POST_FOSSA"
}

/// Display Set Horizontal / Vertical Justification (0072,0717 / 0072,0718)
///
/// PS3.3 Table C.23.3-1 Enumerated Values: LEFT, CENTER, RIGHT horizontally;
/// TOP, CENTER, BOTTOM vertically.
public enum Justification: String, Sendable, Codable {
    case left = "LEFT"
    case center = "CENTER"
    case right = "RIGHT"
    case top = "TOP"
    case bottom = "BOTTOM"

    /// True for a term of Display Set Horizontal Justification (0072,0717)
    public var isHorizontal: Bool { self == .left || self == .center || self == .right }

    /// True for a term of Display Set Vertical Justification (0072,0718)
    public var isVertical: Bool { self == .top || self == .center || self == .bottom }
}
