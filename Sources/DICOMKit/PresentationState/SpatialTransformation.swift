// NEMA-verified: 2026a, checked 2026-09-30 — rotation and flip per PS3.3 2026a Table C.10-6 (any input angle now yields one of the Enumerated Values 0/90/180/270, D38); Displayed Area attributes, Presentation Size Mode terms and the 1C spacing/aspect/magnification conditions per Table C.10-4
//
// SpatialTransformation.swift
// DICOMKit
//
// Created by DICOMKit on 2026-02-04.
// Copyright © 2026 DICOMKit. All rights reserved.
//

import Foundation
import DICOMCore

/// Spatial transformation for image display
///
/// Defines rotation and horizontal flip to apply to the image.
///
/// Reference: PS3.3 Section C.10.6 - Spatial Transformation Module
public struct SpatialTransformation: Sendable, Hashable {
    /// Image rotation in degrees (clockwise)
    ///
    /// Valid values: 0, 90, 180, 270
    public let rotation: Int
    
    /// Whether to flip the image horizontally
    public let horizontalFlip: Bool
    
    /// Initialize a spatial transformation
    ///
    /// - Parameters:
    ///   - rotation: Rotation angle in degrees (0, 90, 180, or 270)
    ///   - horizontalFlip: Whether to flip horizontally
    public init(rotation: Int = 0, horizontalFlip: Bool = false) {
        // Image Rotation (0070,0042) has the Enumerated Values 0, 90, 180 and
        // 270, and negative values are not permitted (PS3.3 2026a Table C.10-6).
        // Normalise into 0..<360 first, then round to the nearest quarter turn
        // (ties upward) and wrap once more, so that 315 gives 0 rather than 360
        // and -135 gives 270 rather than -90.
        let normalizedRotation = ((rotation % 360) + 360) % 360
        self.rotation = (((normalizedRotation + 45) / 90) * 90) % 360
        
        self.horizontalFlip = horizontalFlip
    }
    
    /// Whether the image is rotated
    public var isRotated: Bool {
        rotation != 0
    }
    
    /// Whether the image is flipped
    public var isFlipped: Bool {
        horizontalFlip
    }
    
    /// Whether any transformation is applied
    public var hasTransformation: Bool {
        isRotated || isFlipped
    }
}

/// Displayed area selection
///
/// Defines the portion of the image to display and how to size it.
///
/// Reference: PS3.3 Section C.10.4 - Displayed Area Module
public struct DisplayedArea: Sendable, Hashable {
    /// Top-left corner of the displayed area (column, row)
    public let topLeft: (column: Int, row: Int)
    
    /// Bottom-right corner of the displayed area (column, row)
    public let bottomRight: (column: Int, row: Int)
    
    /// Presentation size mode
    public let sizeMode: PresentationSizeMode

    /// Presentation Pixel Spacing (0070,0101): the physical distance between
    /// pixel centres of the referenced image, adjacent row spacing then adjacent
    /// column spacing, in mm (Table C.10-4; the order is that of 10.7.1.3).
    ///
    /// Type 1C: required when `sizeMode` is `.trueSize`, in which case it is the
    /// distance between pixel centres on the display; may be present for
    /// SCALE TO FIT or MAGNIFY, where it only fixes the pixel aspect ratio.
    public let pixelSpacing: (row: Double, column: Double)?

    /// Presentation Pixel Aspect Ratio (0070,0102): vertical extent then
    /// horizontal extent of a pixel, as integers (Table C.10-4).
    ///
    /// Type 1C: required when `pixelSpacing` is absent. The builder writes 1\1
    /// when neither is given.
    public let pixelAspectRatio: (vertical: Int, horizontal: Int)?

    /// Presentation Pixel Magnification Ratio (0070,0103): displayed pixels per
    /// source pixel, in one dimension (Table C.10-4).
    ///
    /// Type 1C: required when `sizeMode` is `.magnify`.
    public let magnificationRatio: Double?

    /// Initialize a displayed area
    ///
    /// - Parameters:
    ///   - topLeft: Top-left corner (column, row)
    ///   - bottomRight: Bottom-right corner (column, row)
    ///   - sizeMode: How to size the displayed area
    ///   - pixelSpacing: Row and column spacing in mm; required for TRUE SIZE
    ///   - pixelAspectRatio: Vertical\horizontal pixel extent; used when no spacing
    ///   - magnificationRatio: Displayed pixels per source pixel; required for MAGNIFY
    public init(
        topLeft: (column: Int, row: Int),
        bottomRight: (column: Int, row: Int),
        sizeMode: PresentationSizeMode = .scaleToFit,
        pixelSpacing: (row: Double, column: Double)? = nil,
        pixelAspectRatio: (vertical: Int, horizontal: Int)? = nil,
        magnificationRatio: Double? = nil
    ) {
        self.topLeft = topLeft
        self.bottomRight = bottomRight
        self.sizeMode = sizeMode
        self.pixelSpacing = pixelSpacing
        self.pixelAspectRatio = pixelAspectRatio
        self.magnificationRatio = magnificationRatio
    }

    /// Width of the displayed area in pixels
    public var width: Int {
        bottomRight.column - topLeft.column + 1
    }

    /// Height of the displayed area in pixels
    public var height: Int {
        bottomRight.row - topLeft.row + 1
    }

    /// The ratio of a displayed pixel's vertical extent to its horizontal one,
    /// from the spacing when present, else the aspect ratio, else 1 — the
    /// square pixels C.10.4 says the module states explicitly "even if it is 1:1".
    public var verticalToHorizontalAspect: Double {
        if let spacing = pixelSpacing, spacing.column > 0 {
            return spacing.row / spacing.column
        }
        if let ratio = pixelAspectRatio, ratio.horizontal > 0 {
            return Double(ratio.vertical) / Double(ratio.horizontal)
        }
        return 1
    }

    /// Why this area cannot be written as it stands (Table C.10-4 Type 1C).
    public enum ConformanceError: Error, Sendable, Equatable, CustomStringConvertible {
        /// TRUE SIZE without Presentation Pixel Spacing (0070,0101)
        case trueSizeWithoutPixelSpacing
        /// MAGNIFY without Presentation Pixel Magnification Ratio (0070,0103)
        case magnifyWithoutMagnificationRatio

        public var description: String {
            switch self {
            case .trueSizeWithoutPixelSpacing:
                return "Presentation Size Mode TRUE SIZE requires Presentation Pixel Spacing (0070,0101) (PS3.3 Table C.10-4)"
            case .magnifyWithoutMagnificationRatio:
                return "Presentation Size Mode MAGNIFY requires Presentation Pixel Magnification Ratio (0070,0103) (PS3.3 Table C.10-4)"
            }
        }
    }

    /// Checks the Type 1C conditions of Table C.10-4 that only the caller can
    /// satisfy: TRUE SIZE needs a physical spacing and MAGNIFY a ratio. The
    /// aspect-ratio condition is not checked because the builder supplies 1\1.
    public func validate() throws {
        switch sizeMode {
        case .trueSize where pixelSpacing == nil:
            throw ConformanceError.trueSizeWithoutPixelSpacing
        case .magnify where magnificationRatio == nil:
            throw ConformanceError.magnifyWithoutMagnificationRatio
        default:
            break
        }
    }
}

/// Presentation size mode
///
/// The Enumerated Values of Presentation Size Mode (0070,0100), PS3.3 C.10.4:
/// the manner of selection of display size.
///
/// Reference: PS3.3 Section C.10.4 - Displayed Area Module
public enum PresentationSizeMode: String, Sendable, Hashable, CaseIterable {
    /// "the specified area shall be displayed as large as possible within the
    /// available area on the display or window, i.e., magnified or minified if
    /// necessary" (C.10.4)
    case scaleToFit = "SCALE TO FIT"

    /// "the physical size of the rendered image pixels shall be the same on the
    /// screen as specified in Presentation Pixel Spacing (0070,0101)" (C.10.4)
    case trueSize = "TRUE SIZE"

    /// "the factor that shall be used to spatially interpolate image pixels to
    /// create pixels on the display is defined" — by Presentation Pixel
    /// Magnification Ratio (0070,0103) (C.10.4)
    case magnify = "MAGNIFY"
}

// MARK: - Hashable conformance for tuples

extension DisplayedArea {
    public static func == (lhs: DisplayedArea, rhs: DisplayedArea) -> Bool {
        lhs.topLeft.column == rhs.topLeft.column &&
        lhs.topLeft.row == rhs.topLeft.row &&
        lhs.bottomRight.column == rhs.bottomRight.column &&
        lhs.bottomRight.row == rhs.bottomRight.row &&
        lhs.sizeMode == rhs.sizeMode &&
        lhs.pixelSpacing?.row == rhs.pixelSpacing?.row &&
        lhs.pixelSpacing?.column == rhs.pixelSpacing?.column &&
        lhs.pixelAspectRatio?.vertical == rhs.pixelAspectRatio?.vertical &&
        lhs.pixelAspectRatio?.horizontal == rhs.pixelAspectRatio?.horizontal &&
        lhs.magnificationRatio == rhs.magnificationRatio
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(topLeft.column)
        hasher.combine(topLeft.row)
        hasher.combine(bottomRight.column)
        hasher.combine(bottomRight.row)
        hasher.combine(sizeMode)
        hasher.combine(pixelSpacing?.row)
        hasher.combine(pixelSpacing?.column)
        hasher.combine(pixelAspectRatio?.vertical)
        hasher.combine(pixelAspectRatio?.horizontal)
        hasher.combine(magnificationRatio)
    }
}
