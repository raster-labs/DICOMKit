// PresentationStateModelTests.swift
// DICOMStudioTests
//
// Tests for Presentation State models

import Testing
@testable import DICOMStudio
import Foundation

@Suite("PresentationLUTShape Tests")
struct PresentationLUTShapeTests {

    @Test("Identity and Inverse raw values")
    func testRawValues() {
        #expect(PresentationLUTShape.identity.rawValue == "IDENTITY")
        #expect(PresentationLUTShape.inverse.rawValue == "INVERSE")
    }

    @Test("CaseIterable has 2 cases")
    func testCaseCount() {
        #expect(PresentationLUTShape.allCases.count == 2)
    }
}

@Suite("SpatialTransformationType Tests")
struct SpatialTransformationTypeTests {

    @Test("All transformations have raw values")
    func testRawValues() {
        #expect(SpatialTransformationType.none.rawValue == "NONE")
        #expect(SpatialTransformationType.rotate90.rawValue == "ROTATE_90")
        #expect(SpatialTransformationType.rotate180.rawValue == "ROTATE_180")
        #expect(SpatialTransformationType.rotate270.rawValue == "ROTATE_270")
    }

    @Test("CaseIterable has 8 cases")
    func testCaseCount() {
        #expect(SpatialTransformationType.allCases.count == 8)
    }
}

@Suite("PresentationStateType Tests")
struct PresentationStateTypeTests {

    @Test("All types have raw values")
    func testRawValues() {
        #expect(PresentationStateType.grayscale.rawValue == "GSPS")
        #expect(PresentationStateType.color.rawValue == "COLOR")
        #expect(PresentationStateType.pseudoColor.rawValue == "PSEUDO_COLOR")
        #expect(PresentationStateType.blending.rawValue == "BLENDING")
    }

    @Test("CaseIterable has 4 types")
    func testCaseCount() {
        #expect(PresentationStateType.allCases.count == 4)
    }
}

@Suite("VOILUTTransform Tests")
struct VOILUTTransformTests {

    @Test("Creation with defaults")
    func testDefaults() {
        let voi = VOILUTTransform(windowCenter: 40, windowWidth: 400)
        #expect(voi.windowCenter == 40)
        #expect(voi.windowWidth == 400)
        #expect(voi.function == "LINEAR")
    }

    @Test("Creation with sigmoid function")
    func testSigmoid() {
        let voi = VOILUTTransform(windowCenter: 128, windowWidth: 256, function: "SIGMOID")
        #expect(voi.function == "SIGMOID")
    }

    @Test("Equatable")
    func testEquality() {
        let a = VOILUTTransform(windowCenter: 40, windowWidth: 400)
        let b = VOILUTTransform(windowCenter: 40, windowWidth: 400)
        #expect(a == b)
    }
}

@Suite("ModalityLUTTransform Tests")
struct ModalityLUTTransformTests {

    /// Rescale Type (0028,1054) defaults to US, "Unspecified" — a PS3.3 2026a
    /// C.11.1.1.2 Defined Term that claims no unit. HU is CT's alone.
    @Test("Default is slope=1, intercept=0, Rescale Type US (PS3.3 C.11.1.1.2)")
    func testDefaults() {
        let lut = ModalityLUTTransform()
        #expect(lut.rescaleSlope == 1.0)
        #expect(lut.rescaleIntercept == 0.0)
        #expect(lut.rescaleType == "US")
    }

    @Test("Custom values")
    func testCustom() {
        let lut = ModalityLUTTransform(rescaleSlope: 2.0, rescaleIntercept: -1024.0, rescaleType: "US")
        #expect(lut.rescaleSlope == 2.0)
        #expect(lut.rescaleIntercept == -1024.0)
        #expect(lut.rescaleType == "US")
    }
}

@Suite("GSPSModel Tests")
struct GSPSModelTests {

    @Test("Default GSPS")
    func testDefaults() {
        let gsps = GSPSModel()
        #expect(gsps.presentationLUTShape == .identity)
        #expect(gsps.spatialTransformation == .none)
        #expect(gsps.graphicAnnotations.isEmpty)
        #expect(gsps.textAnnotations.isEmpty)
        #expect(gsps.label == "Untitled")
    }

    @Test("GSPS with VOI LUT")
    func testWithVOI() {
        let voi = VOILUTTransform(windowCenter: 40, windowWidth: 80)
        let gsps = GSPSModel(voiLUT: voi)
        #expect(gsps.voiLUT?.windowCenter == 40)
        #expect(gsps.voiLUT?.windowWidth == 80)
    }

    @Test("GSPS with annotations")
    func testWithAnnotations() {
        let graphic = GraphicAnnotation(graphicType: .point, points: [AnnotationPoint(x: 100, y: 100)])
        let text = TextAnnotation(text: "Finding")
        let gsps = GSPSModel(graphicAnnotations: [graphic], textAnnotations: [text])
        #expect(gsps.graphicAnnotations.count == 1)
        #expect(gsps.textAnnotations.count == 1)
    }

    @Test("GSPS with referenced images")
    func testReferencedImages() {
        let ref = ReferencedImage(sopClassUID: "1.2.840.10008.5.1.4.1.1.2", sopInstanceUID: "1.2.3.4.5")
        let gsps = GSPSModel(referencedImages: [ref])
        #expect(gsps.referencedImages.count == 1)
        #expect(gsps.referencedImages[0].sopInstanceUID == "1.2.3.4.5")
    }
}

@Suite("ColorEntry Tests")
struct ColorEntryTests {

    @Test("Color entry creation")
    func testCreation() {
        let color = ColorEntry(red: 255, green: 128, blue: 0)
        #expect(color.red == 255)
        #expect(color.green == 128)
        #expect(color.blue == 0)
    }

    @Test("Color entries are equatable")
    func testEquality() {
        let a = ColorEntry(red: 100, green: 200, blue: 50)
        let b = ColorEntry(red: 100, green: 200, blue: 50)
        #expect(a == b)
    }
}

@Suite("BlendingPresentationStateModel Tests")
struct BlendingPresentationStateModelTests {

    @Test("Default blending opacity")
    func testDefaultOpacity() {
        let blending = BlendingPresentationStateModel()
        #expect(blending.blendingOpacity == 0.5)
    }

    @Test("Opacity clamped to valid range")
    func testOpacityClamping() {
        let tooHigh = BlendingPresentationStateModel(blendingOpacity: 1.5)
        #expect(tooHigh.blendingOpacity == 1.0)

        let tooLow = BlendingPresentationStateModel(blendingOpacity: -0.5)
        #expect(tooLow.blendingOpacity == 0.0)
    }

    @Test("Blending with overlay palette")
    func testOverlayPalette() {
        let blending = BlendingPresentationStateModel(overlayPalette: .hotIron)
        #expect(blending.overlayPalette == .hotIron)
    }
}

@Suite("PresentationStatePalette Tests")
struct PseudoColorPaletteTests {

    @Test("All palette types")
    func testCaseCount() {
        #expect(PresentationStatePalette.allCases.count == 7)
    }

    @Test("Raw values are correct")
    func testRawValues() {
        #expect(PresentationStatePalette.hotIron.rawValue == "HOT_IRON")
        #expect(PresentationStatePalette.rainbow.rawValue == "RAINBOW")
        #expect(PresentationStatePalette.pet.rawValue == "PET")
    }
}
