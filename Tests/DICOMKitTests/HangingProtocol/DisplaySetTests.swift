//
// DisplaySetTests.swift
// DICOMKit
//
// Created by DICOMKit on 2026-02-05.
// Copyright © 2026 DICOMKit. All rights reserved.
//

import XCTest
import DICOMCore
@testable import DICOMKit

final class DisplaySetTests: XCTestCase {
    
    // MARK: - DisplaySet Tests
    
    func test_displaySet_initialization_withRequiredParameters() {
        let displaySet = DisplaySet(number: 1)
        
        XCTAssertEqual(displaySet.number, 1)
        XCTAssertNil(displaySet.label)
        XCTAssertNil(displaySet.presentationGroup)
        XCTAssertNil(displaySet.presentationGroupDescription)
        XCTAssertNil(displaySet.scrollingGroup)
        XCTAssertEqual(displaySet.imageBoxes.count, 0)
    }

    func test_displaySet_initialization_withAllParameters() {
        let imageBox = ImageBox(number: 1, layoutType: .tiled, imageSetNumbers: [1, 2])
        let options = DisplayOptions(showGraphicAnnotations: true)

        let displaySet = DisplaySet(
            number: 1,
            label: "Main Display",
            presentationGroup: 1,
            presentationGroupDescription: "Primary View",
            scrollingGroup: 1,
            imageBoxes: [imageBox],
            displayOptions: options
        )

        XCTAssertEqual(displaySet.number, 1)
        XCTAssertEqual(displaySet.label, "Main Display")
        XCTAssertEqual(displaySet.presentationGroup, 1)
        XCTAssertEqual(displaySet.presentationGroupDescription, "Primary View")
        XCTAssertEqual(displaySet.scrollingGroup, 1)
        XCTAssertEqual(displaySet.imageBoxes.count, 1)
    }

    /// PS3.3 2026a Table C.23.3-1: Partial Data Display Handling (0072,0208) Enumerated Values
    func test_partialDataDisplayHandling_rawValues() {
        XCTAssertEqual(PartialDataDisplayHandling.maintainLayout.rawValue, "MAINTAIN_LAYOUT")
        XCTAssertEqual(PartialDataDisplayHandling.adaptLayout.rawValue, "ADAPT_LAYOUT")
        XCTAssertNil(PartialDataDisplayHandling(rawValue: "DISPLAY"))

        let hangingProtocol = HangingProtocol(name: "P", partialDataDisplayHandling: .adaptLayout)
        XCTAssertEqual(hangingProtocol.partialDataDisplayHandling, .adaptLayout)
        XCTAssertNil(HangingProtocol(name: "P").partialDataDisplayHandling)
    }
    
    func test_displaySet_multipleImageBoxes() {
        let box1 = ImageBox(number: 1, layoutType: .stack)
        let box2 = ImageBox(number: 2, layoutType: .tiled)
        
        let displaySet = DisplaySet(number: 1, imageBoxes: [box1, box2])
        
        XCTAssertEqual(displaySet.imageBoxes.count, 2)
        XCTAssertEqual(displaySet.imageBoxes[0].number, 1)
        XCTAssertEqual(displaySet.imageBoxes[1].number, 2)
    }
    
    // MARK: - ImageBox Tests
    
    func test_imageBox_initialization_withRequiredParameters() {
        let imageBox = ImageBox(number: 1)
        
        XCTAssertEqual(imageBox.number, 1)
        XCTAssertEqual(imageBox.layoutType, .stack)
        XCTAssertEqual(imageBox.imageSetNumbers.count, 0)
        XCTAssertNil(imageBox.tileHorizontalDimension)
        XCTAssertNil(imageBox.tileVerticalDimension)
        XCTAssertNil(imageBox.scrollDirection)
        XCTAssertNil(imageBox.smallScrollType)
        XCTAssertNil(imageBox.smallScrollAmount)
        XCTAssertNil(imageBox.largeScrollType)
        XCTAssertNil(imageBox.largeScrollAmount)
        XCTAssertNil(imageBox.overlapPriority)
        XCTAssertNil(imageBox.cineRelativeToRealTime)
        XCTAssertNil(imageBox.synchronizationGroup)
        XCTAssertNil(imageBox.reformattingOperation)
        XCTAssertNil(imageBox.threeDRenderingType)
        XCTAssertTrue(imageBox.threeDRenderingSubtypes.isEmpty)
    }
    
    func test_imageBox_stackLayout() {
        let imageBox = ImageBox(number: 1, layoutType: .stack, imageSetNumbers: [1])
        
        XCTAssertEqual(imageBox.layoutType, .stack)
        XCTAssertEqual(imageBox.imageSetNumbers, [1])
    }
    
    func test_imageBox_tiledLayout() {
        let imageBox = ImageBox(
            number: 1,
            layoutType: .tiled,
            imageSetNumbers: [1, 2, 3, 4],
            tileHorizontalDimension: 2,
            tileVerticalDimension: 2
        )
        
        XCTAssertEqual(imageBox.layoutType, .tiled)
        XCTAssertEqual(imageBox.tileHorizontalDimension, 2)
        XCTAssertEqual(imageBox.tileVerticalDimension, 2)
        XCTAssertEqual(imageBox.imageSetNumbers.count, 4)
    }
    
    func test_imageBox_cineLayout() {
        let imageBox = ImageBox(number: 1, layoutType: .cine, cineRelativeToRealTime: 1.0)

        XCTAssertEqual(imageBox.layoutType, .cine)
    }

    @available(*, deprecated)
    func test_imageBox_tiledAllLayout_isWrittenAsTiled() {
        let imageBox = ImageBox(number: 1, layoutType: .tiledAll)

        XCTAssertEqual(imageBox.layoutType, .tiledAll)
        XCTAssertEqual(imageBox.layoutType.standardTerm, .tiled)
    }
    
    func test_imageBox_scrollSettings() {
        let imageBox = ImageBox(
            number: 1,
            scrollDirection: .vertical,
            smallScrollType: .image,
            smallScrollAmount: 1,
            largeScrollType: .page,
            largeScrollAmount: 10
        )
        
        XCTAssertEqual(imageBox.scrollDirection, .vertical)
        XCTAssertEqual(imageBox.smallScrollType, .image)
        XCTAssertEqual(imageBox.smallScrollAmount, 1)
        XCTAssertEqual(imageBox.largeScrollType, .page)
        XCTAssertEqual(imageBox.largeScrollAmount, 10)
    }
    
    func test_imageBox_synchronization() {
        let imageBox = ImageBox(number: 1, synchronizationGroup: 1)
        
        XCTAssertEqual(imageBox.synchronizationGroup, 1, "Should support synchronization")
    }
    
    func test_imageBox_cinePlayback() {
        let imageBox = ImageBox(number: 1, cineRelativeToRealTime: 1.5)
        
        XCTAssertEqual(imageBox.cineRelativeToRealTime, 1.5, "Should support cine playback speed")
    }
    
    // MARK: - ImageBoxLayoutType Tests

    /// PS3.3 2026a Table C.23.3-1: Image Box Layout Type (0072,0304) Defined Terms
    func test_imageBoxLayoutType_rawValues() {
        XCTAssertEqual(ImageBoxLayoutType.tiled.rawValue, "TILED")
        XCTAssertEqual(ImageBoxLayoutType.stack.rawValue, "STACK")
        XCTAssertEqual(ImageBoxLayoutType.cine.rawValue, "CINE")
        XCTAssertEqual(ImageBoxLayoutType.processed.rawValue, "PROCESSED")
        XCTAssertEqual(ImageBoxLayoutType.single.rawValue, "SINGLE")
    }

    func test_imageBoxLayoutType_fromString() {
        XCTAssertEqual(ImageBoxLayoutType.reading("TILED"), .tiled)
        XCTAssertEqual(ImageBoxLayoutType.reading("STACK"), .stack)
        XCTAssertEqual(ImageBoxLayoutType.reading("CINE"), .cine)
        XCTAssertEqual(ImageBoxLayoutType.reading("PROCESSED"), .processed)
        XCTAssertEqual(ImageBoxLayoutType.reading("SINGLE"), .single)
        XCTAssertEqual(ImageBoxLayoutType.reading("TILED_ALL"), .tiled, "old DICOMKit spelling")
        XCTAssertNil(ImageBoxLayoutType.reading("INVALID"))
    }

    // MARK: - ScrollDirection Tests

    /// PS3.3 2026a Table C.23.3-1: Image Box Scroll Direction (0072,0310) Enumerated Values
    func test_scrollDirection_rawValues() {
        XCTAssertEqual(ScrollDirection.horizontal.rawValue, "HORIZONTAL")
        XCTAssertEqual(ScrollDirection.vertical.rawValue, "VERTICAL")
    }

    // MARK: - ScrollType Tests

    /// PS3.3 2026a Table C.23.3-1: Image Box Small / Large Scroll Type (0072,0312 / 0316)
    /// Enumerated Values PAGE, ROW_COLUMN, IMAGE
    func test_scrollType_rawValues() {
        XCTAssertEqual(ScrollType.page.rawValue, "PAGE")
        XCTAssertEqual(ScrollType.rowColumn.rawValue, "ROW_COLUMN")
        XCTAssertEqual(ScrollType.image.rawValue, "IMAGE")
    }

    func test_scrollType_fromString() {
        XCTAssertEqual(ScrollType.reading("PAGE"), .page)
        XCTAssertEqual(ScrollType.reading("ROW_COLUMN"), .rowColumn)
        XCTAssertEqual(ScrollType.reading("IMAGE"), .image)
        XCTAssertEqual(ScrollType.reading("FRACTION"), .page, "old DICOMKit spelling")
        XCTAssertNil(ScrollType.reading("INVALID"))
    }

    @available(*, deprecated)
    func test_scrollType_fractionIsWrittenAsPage() {
        XCTAssertEqual(ScrollType.fraction.standardTerm, .page)
        XCTAssertEqual(ScrollType.rowColumn.standardTerm, .rowColumn)
    }

    // MARK: - ReformattingOperation Tests

    /// PS3.3 2026a Table C.23.3-1: Reformatting Thickness / Interval required for SLAB or MPR,
    /// Initial View Direction required for MPR or 3D_RENDERING
    func test_reformattingOperation_mpr() {
        let operation = ReformattingOperation(
            type: .mpr,
            thickness: 5.0,
            interval: 2.5,
            initialViewPlane: .transverse
        )

        XCTAssertEqual(operation.type, .mpr)
        XCTAssertEqual(operation.thickness, 5.0)
        XCTAssertEqual(operation.interval, 2.5)
        XCTAssertEqual(operation.initialViewPlane, .transverse)
    }

    func test_reformattingOperation_slab() {
        let operation = ReformattingOperation(type: .slab, thickness: 10.0, interval: 10.0)

        XCTAssertEqual(operation.type, .slab)
        XCTAssertEqual(operation.thickness, 10.0)
        XCTAssertNil(operation.initialViewPlane)
    }

    func test_reformattingOperation_threeDRendering() {
        let operation = ReformattingOperation(type: .threeDRendering, initialViewPlane: .coronal)

        XCTAssertEqual(operation.type, .threeDRendering)
        XCTAssertEqual(operation.initialViewPlane, .coronal)
    }

    @available(*, deprecated)
    func test_reformattingOperation_deprecatedViewDirectionMaps() {
        let axial = ReformattingOperation(type: .mpr, initialViewDirection: "AXIAL")
        XCTAssertEqual(axial.initialViewPlane, .transverse)
        XCTAssertEqual(axial.initialViewDirection, "TRANSVERSE")

        let unknown = ReformattingOperation(type: .mpr, initialViewDirection: "SIDEWAYS")
        XCTAssertNil(unknown.initialViewPlane, "text that is no Defined Term is dropped")
    }

    // MARK: - ReformattingType Tests

    /// PS3.3 2026a Table C.23.3-1: Reformatting Operation Type (0072,0510) Defined Terms
    func test_reformattingType_standardTerms() {
        XCTAssertEqual(ReformattingType.mpr.rawValue, "MPR")
        XCTAssertEqual(ReformattingType.threeDRendering.rawValue, "3D_RENDERING")
        XCTAssertEqual(ReformattingType.slab.rawValue, "SLAB")
    }

    func test_reformattingType_fromString() {
        XCTAssertEqual(ReformattingType.reading("MPR"), .mpr)
        XCTAssertEqual(ReformattingType.reading("3D_RENDERING"), .threeDRendering)
        XCTAssertEqual(ReformattingType.reading("SLAB"), .slab)
        // Old DICOMKit spellings
        XCTAssertEqual(ReformattingType.reading("CPR"), .mpr)
        XCTAssertEqual(ReformattingType.reading("MIP"), .threeDRendering)
        XCTAssertEqual(ReformattingType.reading("MinIP"), .threeDRendering)
        XCTAssertEqual(ReformattingType.reading("AvgIP"), .threeDRendering)
        XCTAssertNil(ReformattingType.reading("INVALID"))
    }

    /// MIP is a 3D Rendering Type (0072,0520) term; the projections become 3D_RENDERING
    @available(*, deprecated)
    func test_reformattingType_deprecatedCasesMap() {
        XCTAssertEqual(ReformattingType.cpr.standardTerm, .mpr)
        XCTAssertEqual(ReformattingType.mip.standardTerm, .threeDRendering)
        XCTAssertEqual(ReformattingType.minIP.standardTerm, .threeDRendering)
        XCTAssertEqual(ReformattingType.avgIP.standardTerm, .threeDRendering)

        XCTAssertEqual(ReformattingType.mip.impliedRenderingType?.type, .mip)
        XCTAssertEqual(ReformattingType.mip.impliedRenderingType?.subtypes, [])
        XCTAssertEqual(ReformattingType.minIP.impliedRenderingType?.type, .volumeRendering)
        XCTAssertEqual(ReformattingType.minIP.impliedRenderingType?.subtypes, ["MINIP"])
        XCTAssertEqual(ReformattingType.avgIP.impliedRenderingType?.subtypes, ["AVGIP"])
        XCTAssertNil(ReformattingType.mpr.impliedRenderingType)
    }

    // MARK: - ThreeDRenderingType Tests

    /// PS3.3 2026a Table C.23.3-1: 3D Rendering Type (0072,0520) Defined Terms for Value 1
    func test_threeDRenderingType_allValues() {
        XCTAssertEqual(ThreeDRenderingType.mip.rawValue, "MIP")
        XCTAssertEqual(ThreeDRenderingType.surfaceRendering.rawValue, "SURFACE")
        XCTAssertEqual(ThreeDRenderingType.volumeRendering.rawValue, "VOLUME")
    }

    func test_threeDRenderingSubtypes() {
        // "Additional values may be used to identify implementation specific sub-types"
        let box = ImageBox(number: 1, threeDRenderingType: .volumeRendering, threeDRenderingSubtypes: ["SHADED"])
        XCTAssertEqual(box.threeDRenderingType, .volumeRendering)
        XCTAssertEqual(box.threeDRenderingSubtypes, ["SHADED"])
    }

    func test_threeDRenderingType_fromString() {
        XCTAssertEqual(ThreeDRenderingType(rawValue: "VOLUME"), .volumeRendering)
        XCTAssertEqual(ThreeDRenderingType(rawValue: "SURFACE"), .surfaceRendering)
        XCTAssertEqual(ThreeDRenderingType(rawValue: "MIP"), .mip)
        XCTAssertNil(ThreeDRenderingType(rawValue: "INVALID"))
    }
    
    // MARK: - DisplayOptions Tests
    
    func test_displayOptions_initialization_defaults() {
        let options = DisplayOptions()
        
        XCTAssertNil(options.patientOrientation)
        XCTAssertNil(options.voiType)
        XCTAssertNil(options.pseudoColorType)
        XCTAssertFalse(options.showGrayscaleInverted)
        XCTAssertFalse(options.showImageTrueSize)
        XCTAssertTrue(options.showGraphicAnnotations)
        XCTAssertTrue(options.showPatientDemographics)
        XCTAssertTrue(options.showAcquisitionTechniques)
        XCTAssertNil(options.horizontalJustification)
        XCTAssertNil(options.verticalJustification)
    }
    
    /// PS3.3 2026a Table C.23.3-1: VOI Type (0072,0702) Defined Terms
    func test_voiType_definedTerms() {
        XCTAssertEqual(VOIType.lung.rawValue, "LUNG")
        XCTAssertEqual(VOIType.mediastinum.rawValue, "MEDIASTINUM")
        XCTAssertEqual(VOIType.abdomenPelvis.rawValue, "ABDO_PELVIS")
        XCTAssertEqual(VOIType.liver.rawValue, "LIVER")
        XCTAssertEqual(VOIType.softTissue.rawValue, "SOFT_TISSUE")
        XCTAssertEqual(VOIType.bone.rawValue, "BONE")
        XCTAssertEqual(VOIType.brain.rawValue, "BRAIN")
        XCTAssertEqual(VOIType.posteriorFossa.rawValue, "POST_FOSSA")
        XCTAssertEqual(VOIType.allCases.count, 8)

        XCTAssertEqual(DisplayOptions(voiType: "LUNG").voiTypeTerm, .lung)
        XCTAssertNil(DisplayOptions(voiType: "LINEAR").voiTypeTerm, "not a Defined Term, still carried as text")
    }

    func test_displayOptions_initialization_allParameters() {
        let options = DisplayOptions(
            patientOrientation: "L\\P",
            voiType: "LINEAR",
            pseudoColorType: "HOT_METAL",
            showGrayscaleInverted: true,
            showImageTrueSize: true,
            showGraphicAnnotations: false,
            showPatientDemographics: false,
            showAcquisitionTechniques: false,
            horizontalJustification: .center,
            verticalJustification: .top
        )
        
        XCTAssertEqual(options.patientOrientation, "L\\P")
        XCTAssertEqual(options.voiType, "LINEAR")
        XCTAssertEqual(options.pseudoColorType, "HOT_METAL")
        XCTAssertTrue(options.showGrayscaleInverted)
        XCTAssertTrue(options.showImageTrueSize)
        XCTAssertFalse(options.showGraphicAnnotations)
        XCTAssertFalse(options.showPatientDemographics)
        XCTAssertFalse(options.showAcquisitionTechniques)
        XCTAssertEqual(options.horizontalJustification, .center)
        XCTAssertEqual(options.verticalJustification, .top)
    }
    
    // MARK: - Justification Tests

    /// PS3.3 2026a Table C.23.3-1: Display Set Horizontal Justification (0072,0717) LEFT CENTER RIGHT
    func test_justification_horizontalValues() {
        XCTAssertEqual(Justification.left.rawValue, "LEFT")
        XCTAssertEqual(Justification.center.rawValue, "CENTER")
        XCTAssertEqual(Justification.right.rawValue, "RIGHT")
        XCTAssertTrue(Justification.left.isHorizontal)
        XCTAssertTrue(Justification.center.isHorizontal)
        XCTAssertFalse(Justification.top.isHorizontal)
    }

    /// PS3.3 2026a Table C.23.3-1: Display Set Vertical Justification (0072,0718) TOP CENTER BOTTOM
    func test_justification_verticalValues() {
        XCTAssertEqual(Justification.top.rawValue, "TOP")
        XCTAssertEqual(Justification.center.rawValue, "CENTER")
        XCTAssertEqual(Justification.bottom.rawValue, "BOTTOM")
        XCTAssertTrue(Justification.bottom.isVertical)
        XCTAssertTrue(Justification.center.isVertical)
        XCTAssertFalse(Justification.right.isVertical)
    }
    
    func test_justification_fromString() {
        XCTAssertEqual(Justification(rawValue: "LEFT"), .left)
        XCTAssertEqual(Justification(rawValue: "CENTER"), .center)
        XCTAssertEqual(Justification(rawValue: "RIGHT"), .right)
        XCTAssertNil(Justification(rawValue: "INVALID"))
    }
}
