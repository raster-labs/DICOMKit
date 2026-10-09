// PresentationStateHelpers.swift
// DICOMStudio
//
// DICOM Studio — Platform-independent presentation state transformation helpers
//
// NEMA-verified: 2026a, checked 2026-10-05 — `applyLinearVOI` thresholds and ramp are the C.11.2.1.2.1 pseudo-code verbatim (upper bound was c + w/2, the text has c − 0.5 + (w−1)/2: corrected; w ≥ 1 enforced); `applySigmoidVOI` and `applyLinearExactVOI` match the C.11.2.1.3.1 / C.11.2.1.3.2 pseudo-code; `applyVOILUT` dispatches on the three C.11.2 VOI LUT Function terms LINEAR / LINEAR_EXACT / SIGMOID; `applyPresentationLUT` INVERSE = maximum − output (C.11.6.1.2); `rotationAngle` yields the four C.10.6 Image Rotation values and `transformPoint` now rotates before it flips, as Table C.10-6 orders it (flip was applied first: corrected); `applyGSPSPipeline`'s /4095 fallback when no VOI is given is a display convenience the standard does not define (PS3.4 N.2.1.3 makes an absent VOI the identity) and is documented as such; checked by Scripts/diff_studio_g2_viewer.py

import Foundation

/// Platform-independent helpers for Presentation State transformations.
///
/// Implements VOI LUT, Modality LUT, Presentation LUT, and spatial transformation
/// calculations per DICOM PS3.3 C.11.
public enum PresentationStateHelpers: Sendable {

    // MARK: - VOI LUT

    /// Applies the LINEAR VOI LUT function to a pixel value.
    ///
    /// The pseudo-code of PS3.3 C.11.2.1.2.1, with ymin = 0 and ymax = 1:
    ///
    ///     if (x <= c - 0.5 - (w-1)/2), then y = ymin
    ///     else if (x > c - 0.5 + (w-1)/2), then y = ymax
    ///     else y = ((x - (c - 0.5)) / (w-1) + 0.5) * (ymax - ymin) + ymin
    ///
    /// "Window Width (0028,1051) shall always be greater than or equal to 1";
    /// a width of exactly 1 is the threshold at c − 0.5 and never reaches the
    /// ramp, so there is no division by zero. The upper threshold is one unit
    /// below `c + w/2` — a window of 1–100 maps 100 to ymax, not past it.
    ///
    /// - Parameters:
    ///   - pixelValue: Input value `x` — the output of the Modality LUT.
    ///   - center: Window Center `c`.
    ///   - width: Window Width `w` (≥ 1; anything smaller yields 0).
    /// - Returns: Output value in range [0, 1].
    public static func applyLinearVOI(pixelValue: Double, center: Double, width: Double) -> Double {
        let x = pixelValue, c = center, w = width
        guard w >= 1 else { return 0.0 }

        if x <= c - 0.5 - (w - 1) / 2 {
            return 0.0
        } else if x > c - 0.5 + (w - 1) / 2 {
            return 1.0
        } else {
            return (x - (c - 0.5)) / (w - 1) + 0.5
        }
    }

    /// Applies the SIGMOID VOI LUT function to a pixel value.
    ///
    /// PS3.3 C.11.2.1.3.1: y = (ymax − ymin) / (1 + exp(−4 (x − c) / w)) + ymin,
    /// with w > 0.
    ///
    /// - Parameters:
    ///   - pixelValue: Input pixel value.
    ///   - center: Window center.
    ///   - width: Window width (must be > 0).
    /// - Returns: Output value in range [0, 1].
    public static func applySigmoidVOI(pixelValue: Double, center: Double, width: Double) -> Double {
        guard width > 0 else { return 0.0 }
        let exponent = -4.0 * (pixelValue - center) / width
        return 1.0 / (1.0 + exp(exponent))
    }

    /// Applies the LINEAR_EXACT VOI LUT function.
    ///
    /// The pseudo-code of PS3.3 C.11.2.1.3.2, with w > 0:
    ///
    ///     if (x <= c - w/2), then y = ymin
    ///     else if (x > c + w/2), then y = ymax
    ///     else y = ((x - c) / w + 0.5) * (ymax - ymin) + ymin
    ///
    /// - Parameters:
    ///   - pixelValue: Input pixel value.
    ///   - center: Window center.
    ///   - width: Window width (must be > 0).
    /// - Returns: Output value in range [0, 1].
    public static func applyLinearExactVOI(pixelValue: Double, center: Double, width: Double) -> Double {
        guard width > 0 else { return 0.0 }

        if pixelValue <= center - width / 2.0 {
            return 0.0
        } else if pixelValue > center + width / 2.0 {
            return 1.0
        } else {
            return (pixelValue - center) / width + 0.5
        }
    }

    /// Selects and applies the appropriate VOI LUT function.
    ///
    /// The three Defined Terms of VOI LUT Function (0028,1056), PS3.3 C.11.2:
    /// LINEAR (also when the Attribute is absent, C.11.2.1.3), LINEAR_EXACT
    /// and SIGMOID.
    ///
    /// - Parameters:
    ///   - pixelValue: Input pixel value.
    ///   - transform: VOI LUT transform parameters.
    /// - Returns: Output value in range [0, 1].
    public static func applyVOILUT(pixelValue: Double, transform: VOILUTTransform) -> Double {
        switch transform.function.uppercased() {
        case "SIGMOID":
            return applySigmoidVOI(pixelValue: pixelValue, center: transform.windowCenter, width: transform.windowWidth)
        case "LINEAR_EXACT":
            return applyLinearExactVOI(pixelValue: pixelValue, center: transform.windowCenter, width: transform.windowWidth)
        default:
            return applyLinearVOI(pixelValue: pixelValue, center: transform.windowCenter, width: transform.windowWidth)
        }
    }

    // MARK: - Modality LUT

    /// Applies a modality LUT (rescale slope/intercept) transformation.
    ///
    /// output = slope * storedValue + intercept
    ///
    /// - Parameters:
    ///   - storedValue: Stored pixel value.
    ///   - transform: Modality LUT transform.
    /// - Returns: Transformed value.
    public static func applyModalityLUT(storedValue: Double, transform: ModalityLUTTransform) -> Double {
        transform.rescaleSlope * storedValue + transform.rescaleIntercept
    }

    // MARK: - Presentation LUT

    /// Applies a Presentation LUT shape transformation.
    ///
    /// PS3.3 C.11.6.1.2: INVERSE "shall mean the same as a Value of IDENTITY,
    /// except that the minimum output value shall convey the meaning of the
    /// maximum available luminance", i.e. P-Value = maximum value − output value.
    ///
    /// - Parameters:
    ///   - value: Input value in range [0, 1].
    ///   - shape: Presentation LUT shape.
    /// - Returns: Transformed value in range [0, 1].
    public static func applyPresentationLUT(value: Double, shape: PresentationLUTShape) -> Double {
        switch shape {
        case .identity:
            return value
        case .inverse:
            return 1.0 - value
        }
    }

    // MARK: - Spatial Transformations

    /// Computes rotation angle in degrees for a spatial transformation.
    ///
    /// One of the four Image Rotation (0070,0042) Enumerated Values 0, 90, 180,
    /// 270 (PS3.3 C.10.6): clockwise, "before any Image Horizontal Flip".
    ///
    /// - Parameter transformation: The spatial transformation type.
    /// - Returns: Rotation angle in degrees.
    public static func rotationAngle(for transformation: SpatialTransformationType) -> Double {
        switch transformation {
        case .none: return 0.0
        case .rotate90, .rotate90FlipH: return 90.0
        case .rotate180: return 180.0
        case .rotate270, .rotate270FlipH: return 270.0
        case .flipHorizontal, .flipVertical: return 0.0
        }
    }

    /// Returns whether a spatial transformation includes a horizontal flip.
    ///
    /// - Parameter transformation: The spatial transformation type.
    /// - Returns: True if horizontally flipped.
    public static func isFlippedHorizontally(_ transformation: SpatialTransformationType) -> Bool {
        switch transformation {
        case .flipHorizontal, .rotate90FlipH, .rotate270FlipH:
            return true
        default:
            return false
        }
    }

    /// Returns whether a spatial transformation includes a vertical flip.
    ///
    /// - Parameter transformation: The spatial transformation type.
    /// - Returns: True if vertically flipped.
    public static func isFlippedVertically(_ transformation: SpatialTransformationType) -> Bool {
        transformation == .flipVertical
    }

    /// Transforms a point by a spatial transformation.
    ///
    /// In the order PS3.3 Table C.10-6 states: Image Rotation (0070,0042) turns
    /// the image clockwise "before any Image Horizontal Flip (0070,0041) is
    /// applied", and the flip then mirrors the *rotated* image "such that the
    /// left side of the image becomes the right side". A quarter turn swaps
    /// the sides, so the flip is about the rotated width. The vertical flip,
    /// which C.10.6 has no value for (it is ROTATE_180 + FLIP_H), is kept as
    /// a mirror about the height.
    ///
    /// - Parameters:
    ///   - point: Input point.
    ///   - transformation: Spatial transformation to apply.
    ///   - imageWidth: Image width in pixels.
    ///   - imageHeight: Image height in pixels.
    /// - Returns: Transformed point.
    public static func transformPoint(
        _ point: AnnotationPoint,
        transformation: SpatialTransformationType,
        imageWidth: Double,
        imageHeight: Double
    ) -> AnnotationPoint {
        var x = point.x
        var y = point.y

        // Rotation first (clockwise), as Table C.10-6 orders it.
        var rotatedWidth = imageWidth
        var rotatedHeight = imageHeight
        switch rotationAngle(for: transformation) {
        case 90:
            (x, y) = (imageHeight - y, x)
            (rotatedWidth, rotatedHeight) = (imageHeight, imageWidth)
        case 180:
            (x, y) = (imageWidth - x, imageHeight - y)
        case 270:
            (x, y) = (y, imageWidth - x)
            (rotatedWidth, rotatedHeight) = (imageHeight, imageWidth)
        default:
            break
        }

        // Then the flip, about the rotated image's edges.
        if isFlippedHorizontally(transformation) {
            x = rotatedWidth - x
        }
        if isFlippedVertically(transformation) {
            y = rotatedHeight - y
        }
        return AnnotationPoint(x: x, y: y)
    }

    // MARK: - Full Pipeline

    /// Applies the full GSPS rendering pipeline to a pixel value.
    ///
    /// Pipeline: Stored Value → Modality LUT → VOI LUT → Presentation LUT
    ///
    /// - Parameters:
    ///   - storedValue: Original stored pixel value.
    ///   - modalityLUT: Optional modality LUT transform.
    ///   - voiLUT: Optional VOI LUT transform.
    ///   - presentationLUTShape: Presentation LUT shape.
    /// - Returns: Output value in range [0, 1].
    public static func applyGSPSPipeline(
        storedValue: Double,
        modalityLUT: ModalityLUTTransform?,
        voiLUT: VOILUTTransform?,
        presentationLUTShape: PresentationLUTShape
    ) -> Double {
        // Step 1: Modality LUT
        var value = storedValue
        if let modLUT = modalityLUT {
            value = applyModalityLUT(storedValue: value, transform: modLUT)
        }

        // Step 2: VOI LUT
        if let voi = voiLUT {
            value = applyVOILUT(pixelValue: value, transform: voi)
        } else {
            // No VOI in the state means the identity (PS3.4 N.2.1.3), whose
            // output range the standard leaves to the Modality LUT; this
            // helper has to land in [0, 1], so a 12-bit range is assumed. A
            // display convenience, not a value the standard defines.
            value = max(0.0, min(1.0, value / 4095.0))
        }

        // Step 3: Presentation LUT
        value = applyPresentationLUT(value: value, shape: presentationLUTShape)

        return value
    }

    // MARK: - Display Text

    /// Returns a display label for a presentation state type.
    ///
    /// - Parameter type: Presentation state type.
    /// - Returns: Human-readable label.
    public static func typeLabel(for type: PresentationStateType) -> String {
        switch type {
        case .grayscale: return "Grayscale (GSPS)"
        case .color: return "Color"
        case .pseudoColor: return "Pseudo-Color"
        case .blending: return "Blending"
        }
    }

    /// Returns a display label for a spatial transformation.
    ///
    /// - Parameter transformation: Spatial transformation type.
    /// - Returns: Human-readable label.
    public static func transformLabel(for transformation: SpatialTransformationType) -> String {
        switch transformation {
        case .none: return "None"
        case .rotate90: return "Rotate 90°"
        case .rotate180: return "Rotate 180°"
        case .rotate270: return "Rotate 270°"
        case .flipHorizontal: return "Flip Horizontal"
        case .flipVertical: return "Flip Vertical"
        case .rotate90FlipH: return "Rotate 90° + Flip H"
        case .rotate270FlipH: return "Rotate 270° + Flip H"
        }
    }

    /// Returns a display label for a presentation LUT shape.
    ///
    /// - Parameter shape: Presentation LUT shape.
    /// - Returns: Human-readable label.
    public static func lutShapeLabel(for shape: PresentationLUTShape) -> String {
        switch shape {
        case .identity: return "Identity"
        case .inverse: return "Inverse"
        }
    }
}
