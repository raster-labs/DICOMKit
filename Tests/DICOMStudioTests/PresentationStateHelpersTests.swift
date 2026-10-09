// PresentationStateHelpersTests.swift
// DICOMStudioTests
//
// Tests for PresentationStateHelpers

import Testing
@testable import DICOMStudio
import Foundation

@Suite("PresentationStateHelpers VOI LUT Tests")
struct PresentationStateVOITests {

    @Test("Linear VOI - below window")
    func testLinearBelow() {
        let result = PresentationStateHelpers.applyLinearVOI(pixelValue: 0, center: 40, width: 80)
        #expect(result == 0.0)
    }

    @Test("Linear VOI - above window")
    func testLinearAbove() {
        let result = PresentationStateHelpers.applyLinearVOI(pixelValue: 100, center: 40, width: 80)
        #expect(result == 1.0)
    }

    @Test("Linear VOI - at center")
    func testLinearCenter() {
        let result = PresentationStateHelpers.applyLinearVOI(pixelValue: 40, center: 40, width: 80)
        #expect(result > 0.4)
        #expect(result < 0.6)
    }

    @Test("Linear VOI - zero width returns 0")
    func testLinearZeroWidth() {
        let result = PresentationStateHelpers.applyLinearVOI(pixelValue: 100, center: 40, width: 0)
        #expect(result == 0.0)
    }

    /// PS3.3 2026a C.11.2.1.2.1 pseudo-code, ymin 0, ymax 1: the thresholds are
    /// c − 0.5 ∓ (w − 1)/2, so for c 50.5, w 100 they sit at 0.5 and 99.5; the
    /// ramp (x − 50)/99 + 0.5 meets 0 and 1 exactly there ("without any
    /// discontinuity at the boundaries") and never exceeds 1. The old upper
    /// threshold, c + w/2 = 100.5, let x = 100 reach 100/99.
    @Test("Linear VOI thresholds are c − 0.5 ∓ (w − 1)/2 (PS3.3 C.11.2.1.2.1)")
    func testLinearThresholdsPerStandard() {
        func y(_ x: Double) -> Double {
            PresentationStateHelpers.applyLinearVOI(pixelValue: x, center: 50.5, width: 100)
        }
        #expect(y(0) == 0.0)                       // x <= 0.5 → ymin
        #expect(y(0.5) == 0.0)
        #expect(abs(y(1) - 1.0 / 198.0) < 1e-12)   // (1 − 50)/99 + 0.5
        #expect(abs(y(99.5) - 1.0) < 1e-12)        // the ramp meets ymax at the threshold
        #expect(y(99) < 1.0)
        #expect(y(100) == 1.0)                     // x > 99.5 → ymax (was 100/99)
        #expect(y(101) == 1.0)
        // The standard's worked example: c=2048, w=4096 → x <= 0 is 0, x > 4095 is 1.
        #expect(PresentationStateHelpers.applyLinearVOI(pixelValue: 0, center: 2048, width: 4096) == 0.0)
        #expect(PresentationStateHelpers.applyLinearVOI(pixelValue: 4096, center: 2048, width: 4096) == 1.0)
        #expect(PresentationStateHelpers.applyLinearVOI(pixelValue: 4095, center: 2048, width: 4096) == 1.0)
        let mid = PresentationStateHelpers.applyLinearVOI(pixelValue: 2047.5, center: 2048, width: 4096)
        #expect(abs(mid - 0.5) < 1e-12)
    }

    /// "When Window Width (0028,1051) is equal to 1, they specify a threshold
    /// below which input values will be displayed as the minimum output value"
    /// — c=2048, w=1: x <= 2047.5 is 0, x > 2047.5 is 1, no division by zero.
    @Test("Linear VOI with width 1 is a threshold at c − 0.5 (PS3.3 C.11.2.1.2.1)")
    func testLinearWidthOneIsThreshold() {
        #expect(PresentationStateHelpers.applyLinearVOI(pixelValue: 2047.5, center: 2048, width: 1) == 0.0)
        #expect(PresentationStateHelpers.applyLinearVOI(pixelValue: 2047.6, center: 2048, width: 1) == 1.0)
        #expect(PresentationStateHelpers.applyLinearVOI(pixelValue: 2048, center: 2048, width: 1) == 1.0)
    }

    @Test("Sigmoid VOI - at center")
    func testSigmoidCenter() {
        let result = PresentationStateHelpers.applySigmoidVOI(pixelValue: 128, center: 128, width: 256)
        #expect(abs(result - 0.5) < 0.01)
    }

    @Test("Sigmoid VOI - far above center")
    func testSigmoidHigh() {
        let result = PresentationStateHelpers.applySigmoidVOI(pixelValue: 1000, center: 128, width: 256)
        #expect(result > 0.9)
    }

    @Test("Sigmoid VOI - zero width returns 0")
    func testSigmoidZeroWidth() {
        let result = PresentationStateHelpers.applySigmoidVOI(pixelValue: 100, center: 40, width: 0)
        #expect(result == 0.0)
    }

    @Test("Linear exact VOI - at center")
    func testLinearExactCenter() {
        let result = PresentationStateHelpers.applyLinearExactVOI(pixelValue: 40, center: 40, width: 80)
        #expect(abs(result - 0.5) < 0.01)
    }

    @Test("Apply VOI LUT dispatches to correct function")
    func testApplyVOIDispatch() {
        let linearResult = PresentationStateHelpers.applyVOILUT(
            pixelValue: 40,
            transform: VOILUTTransform(windowCenter: 40, windowWidth: 80, function: "LINEAR")
        )
        #expect(linearResult > 0.0)

        let sigmoidResult = PresentationStateHelpers.applyVOILUT(
            pixelValue: 128,
            transform: VOILUTTransform(windowCenter: 128, windowWidth: 256, function: "SIGMOID")
        )
        #expect(abs(sigmoidResult - 0.5) < 0.01)
    }
}

@Suite("PresentationStateHelpers Modality LUT Tests")
struct PresentationStateModalityTests {

    @Test("Identity modality LUT")
    func testIdentity() {
        let result = PresentationStateHelpers.applyModalityLUT(
            storedValue: 1000,
            transform: ModalityLUTTransform()
        )
        #expect(result == 1000.0)
    }

    @Test("CT Hounsfield units")
    func testHounsfieldUnits() {
        let result = PresentationStateHelpers.applyModalityLUT(
            storedValue: 1024,
            transform: ModalityLUTTransform(rescaleSlope: 1.0, rescaleIntercept: -1024.0)
        )
        #expect(result == 0.0)
    }
}

@Suite("PresentationStateHelpers Presentation LUT Tests")
struct PresentationStatePLUTTests {

    @Test("Identity LUT")
    func testIdentity() {
        let result = PresentationStateHelpers.applyPresentationLUT(value: 0.7, shape: .identity)
        #expect(result == 0.7)
    }

    @Test("Inverse LUT")
    func testInverse() {
        let result = PresentationStateHelpers.applyPresentationLUT(value: 0.7, shape: .inverse)
        #expect(abs(result - 0.3) < 0.001)
    }
}

@Suite("PresentationStateHelpers Spatial Transform Tests")
struct PresentationStateSpatialTests {

    @Test("No rotation angle")
    func testNoRotation() {
        #expect(PresentationStateHelpers.rotationAngle(for: .none) == 0.0)
    }

    @Test("90 degree rotation")
    func testRotate90() {
        #expect(PresentationStateHelpers.rotationAngle(for: .rotate90) == 90.0)
    }

    @Test("180 degree rotation")
    func testRotate180() {
        #expect(PresentationStateHelpers.rotationAngle(for: .rotate180) == 180.0)
    }

    @Test("270 degree rotation")
    func testRotate270() {
        #expect(PresentationStateHelpers.rotationAngle(for: .rotate270) == 270.0)
    }

    @Test("Horizontal flip detection")
    func testFlipH() {
        #expect(PresentationStateHelpers.isFlippedHorizontally(.flipHorizontal))
        #expect(PresentationStateHelpers.isFlippedHorizontally(.rotate90FlipH))
        #expect(!PresentationStateHelpers.isFlippedHorizontally(.none))
        #expect(!PresentationStateHelpers.isFlippedHorizontally(.rotate180))
    }

    @Test("Vertical flip detection")
    func testFlipV() {
        #expect(PresentationStateHelpers.isFlippedVertically(.flipVertical))
        #expect(!PresentationStateHelpers.isFlippedVertically(.none))
    }

    @Test("Point transformation - no transform")
    func testPointNoTransform() {
        let point = AnnotationPoint(x: 100, y: 200)
        let result = PresentationStateHelpers.transformPoint(
            point, transformation: .none, imageWidth: 512, imageHeight: 512
        )
        #expect(result.x == 100)
        #expect(result.y == 200)
    }

    @Test("Point transformation - flip horizontal")
    func testPointFlipH() {
        let point = AnnotationPoint(x: 100, y: 200)
        let result = PresentationStateHelpers.transformPoint(
            point, transformation: .flipHorizontal, imageWidth: 512, imageHeight: 512
        )
        #expect(result.x == 412) // 512 - 100
        #expect(result.y == 200)
    }

    /// PS3.3 2026a Table C.10-6: Image Rotation turns the image clockwise
    /// "before any Image Horizontal Flip (0070,0041) is applied", and the flip
    /// mirrors the rotated image "such that the left side of the image becomes
    /// the right side". On a 512 × 256 image, (100, 200) turned 90° clockwise is
    /// (256 − 200, 100) = (56, 100) in a 256-wide image; flipped: (200, 100).
    /// Flipping first and turning after gave (56, 412).
    @Test("Rotation is applied before the horizontal flip (PS3.3 Table C.10-6)")
    func testRotateThenFlipOrder() {
        let point = AnnotationPoint(x: 100, y: 200)
        let rotated = PresentationStateHelpers.transformPoint(
            point, transformation: .rotate90, imageWidth: 512, imageHeight: 256)
        #expect(rotated.x == 56)
        #expect(rotated.y == 100)
        let rotatedFlipped = PresentationStateHelpers.transformPoint(
            point, transformation: .rotate90FlipH, imageWidth: 512, imageHeight: 256)
        #expect(rotatedFlipped.x == 200)
        #expect(rotatedFlipped.y == 100)
        let rotated270Flipped = PresentationStateHelpers.transformPoint(
            point, transformation: .rotate270FlipH, imageWidth: 512, imageHeight: 256)
        // 270° clockwise: (y, W − x) = (200, 412); flipped about the 256 width: (56, 412).
        #expect(rotated270Flipped.x == 56)
        #expect(rotated270Flipped.y == 412)
    }
}

@Suite("PresentationStateHelpers Pipeline Tests")
struct PresentationStatePipelineTests {

    @Test("Full GSPS pipeline")
    func testFullPipeline() {
        let result = PresentationStateHelpers.applyGSPSPipeline(
            storedValue: 1064,
            modalityLUT: ModalityLUTTransform(rescaleSlope: 1.0, rescaleIntercept: -1024.0),
            voiLUT: VOILUTTransform(windowCenter: 40, windowWidth: 400),
            presentationLUTShape: .identity
        )
        // After modality LUT: 1064 - 1024 = 40 (center of window)
        #expect(result > 0.4)
        #expect(result < 0.6)
    }

    @Test("Pipeline with inverse LUT")
    func testPipelineInverse() {
        let identity = PresentationStateHelpers.applyGSPSPipeline(
            storedValue: 2048,
            modalityLUT: nil,
            voiLUT: VOILUTTransform(windowCenter: 2048, windowWidth: 4096),
            presentationLUTShape: .identity
        )
        let inverse = PresentationStateHelpers.applyGSPSPipeline(
            storedValue: 2048,
            modalityLUT: nil,
            voiLUT: VOILUTTransform(windowCenter: 2048, windowWidth: 4096),
            presentationLUTShape: .inverse
        )
        #expect(abs(identity + inverse - 1.0) < 0.01)
    }
}

@Suite("PresentationStateHelpers Display Text Tests")
struct PresentationStateDisplayTests {

    @Test("Type labels")
    func testTypeLabels() {
        #expect(PresentationStateHelpers.typeLabel(for: .grayscale) == "Grayscale (GSPS)")
        #expect(PresentationStateHelpers.typeLabel(for: .color) == "Color")
        #expect(PresentationStateHelpers.typeLabel(for: .pseudoColor) == "Pseudo-Color")
        #expect(PresentationStateHelpers.typeLabel(for: .blending) == "Blending")
    }

    @Test("Transform labels")
    func testTransformLabels() {
        #expect(PresentationStateHelpers.transformLabel(for: .none) == "None")
        #expect(PresentationStateHelpers.transformLabel(for: .rotate90) == "Rotate 90°")
    }

    @Test("LUT shape labels")
    func testLUTShapeLabels() {
        #expect(PresentationStateHelpers.lutShapeLabel(for: .identity) == "Identity")
        #expect(PresentationStateHelpers.lutShapeLabel(for: .inverse) == "Inverse")
    }
}
