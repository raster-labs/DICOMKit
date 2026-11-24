// ViewerDrawnAnnotationEditingTests.swift
// DICOMStudioTests
//
// Editing drawn annotations by image identity — the address the main viewer
// uses, since an image on screen need not be marked for print. The film's
// mark-ID paths already have their own coverage; these pin that the key-based
// paths work with *no marks at all*, and that the two address the same
// storage.

import Testing
import Foundation
import DICOMCore
import DICOMKit
@testable import DICOMStudio
import DICOMPrintKit

@MainActor
@Suite("Viewer Drawn Annotation Editing Tests")
struct ViewerDrawnAnnotationEditingTests {

    private let key = ImageAnnotationKey(filePath: "/study/slice42.dcm", frameIndex: 0)

    @Test("An image needs no mark to be drawn on")
    func testDrawingWithoutAnyMarks() {
        let selection = PrintSelectionModel()
        #expect(selection.items.isEmpty)

        let textID = selection.addTextAnnotation(
            forKey: key, at: PrintOverlayPoint(x: 0.3, y: 0.4))
        selection.setAnnotationText("Nodule", id: textID, forKey: key)
        let arrowID = selection.addArrowAnnotation(
            forKey: key,
            from: PrintOverlayPoint(x: 0.1, y: 0.1),
            to: PrintOverlayPoint(x: 0.5, y: 0.5))

        let drawn = selection.annotations(forKey: key)
        #expect(drawn.map(\.id) == [textID, arrowID])
        #expect(drawn.first?.text == "Nodule")
    }

    @Test("Key-based moves land where mark-based moves would")
    func testMovingByKey() {
        let selection = PrintSelectionModel()
        let id = selection.addTextAnnotation(
            forKey: key, at: PrintOverlayPoint(x: 0.3, y: 0.4))
        selection.setAnnotationText("Words", id: id, forKey: key)

        selection.moveAnnotation(id, forKey: key, dx: 0.1, dy: -0.1)

        let moved = selection.annotations(forKey: key).first
        #expect(abs((moved?.start.x ?? 0) - 0.4) < 1e-9)
        #expect(abs((moved?.start.y ?? 0) - 0.3) < 1e-9)
    }

    @Test("An arrow's ends re-aim independently by key")
    func testArrowEndsByKey() {
        let selection = PrintSelectionModel()
        let id = selection.addArrowAnnotation(
            forKey: key,
            from: PrintOverlayPoint(x: 0.1, y: 0.1),
            to: PrintOverlayPoint(x: 0.5, y: 0.5))

        selection.moveArrowEnd(id, forKey: key, isHead: true,
                               to: PrintOverlayPoint(x: 0.9, y: 0.2))

        let arrow = selection.annotations(forKey: key).first
        #expect(arrow?.start == PrintOverlayPoint(x: 0.1, y: 0.1))
        #expect(arrow?.end == PrintOverlayPoint(x: 0.9, y: 0.2))
    }

    /// The bug the key-based delete fixes: the selected annotation lives on an
    /// unmarked image, and the old path required a mark to name — so the
    /// delete key did nothing in the viewer.
    @Test("Deleting the selection works with no mark to name")
    func testRemoveSelectedWithoutAMark() {
        let selection = PrintSelectionModel()
        let id = selection.addArrowAnnotation(
            forKey: key,
            from: PrintOverlayPoint(x: 0.1, y: 0.1),
            to: PrintOverlayPoint(x: 0.5, y: 0.5))
        #expect(selection.selectedAnnotationID == id)

        #expect(selection.removeSelectedAnnotation())
        #expect(selection.annotations(forKey: key).isEmpty)
        #expect(selection.selectedAnnotationID == nil)
    }

    @Test("The selection's location names the image it lives on")
    func testSelectedAnnotationLocation() {
        let selection = PrintSelectionModel()
        let id = selection.addArrowAnnotation(
            forKey: key,
            from: PrintOverlayPoint(x: 0.1, y: 0.1),
            to: PrintOverlayPoint(x: 0.5, y: 0.5))

        let location = selection.selectedAnnotationLocation
        #expect(location?.key == key)
        #expect(location?.annotation.id == id)
    }

    /// Both screens edit one storage: a mark whose `annotationKey` matches
    /// sees exactly what the viewer drew, and vice versa.
    @Test("Mark-based and key-based paths address the same annotations")
    func testSharedStorageAcrossAddressingModes() {
        let selection = PrintSelectionModel()
        let item = PrintSelectionItem(filePath: "/study/slice42.dcm", frameIndex: 0)
        _ = selection.add(item)

        let id = selection.addTextAnnotation(
            forKey: key, at: PrintOverlayPoint(x: 0.3, y: 0.4))
        selection.setAnnotationText("From the viewer", id: id, forKey: key)

        #expect(selection.annotations(forItemID: item.id).map(\.text)
                == ["From the viewer"])

        selection.setAnnotationText("Edited on the film", id: id, forItemID: item.id)
        #expect(selection.annotations(forKey: key).map(\.text)
                == ["Edited on the film"])
    }

    @Test("Colour and scale set by key become the defaults for the next annotation")
    func testStyleByKeyUpdatesDefaults() {
        let selection = PrintSelectionModel()
        let id = selection.addTextAnnotation(
            forKey: key, at: PrintOverlayPoint(x: 0.3, y: 0.4))
        selection.setAnnotationText("Words", id: id, forKey: key)

        selection.setAnnotationColor(.cyan, id: id, forKey: key)
        selection.setAnnotationScale(0.08, id: id, forKey: key)

        #expect(selection.annotationColor == .cyan)
        #expect(abs(selection.annotationScale - 0.08) < 1e-9)
        let styled = selection.annotations(forKey: key).first
        #expect(styled?.color == .cyan)
        #expect(abs((styled?.scale ?? 0) - 0.08) < 1e-9)
    }

    @Test("Length tool appears in ImageViewerDragTool with ruler icon and L shortcut")
    func testLengthToolInDragTools() {
        let lengthTool = ImageViewerDragTool.length
        #expect(lengthTool.displayName == "Length")
        #expect(lengthTool.symbolName == "ruler")
        #expect(lengthTool.shortcut == "l")
        #expect(lengthTool.isDrawing)
        #expect(ImageViewerDragTool.allCases.contains(.length))
        #if os(macOS)
        #expect(lengthTool.cursorSymbolName == "scope")
        #expect(lengthTool.activeSymbolName == "dot.scope")
        #expect(lengthTool.cursor(isDragging: false) !== lengthTool.cursor(isDragging: true))
        #endif
    }

    @Test("Drawing and adjusting a length measurement computes physical mm or pixel distance")
    func testLengthAnnotationDrawingAndMeasurement() {
        let vm = ImageViewerViewModel()
        vm.filePath = "/study/slice42.dcm"
        vm.imageColumns = 512
        vm.imageRows = 512

        // Uncalibrated image -> measures in pixels
        let start = PrintOverlayPoint(x: 0.25, y: 0.5)
        let end = PrintOverlayPoint(x: 0.75, y: 0.5)
        let id = vm.addDrawnLengthAnnotation(from: start, to: end)
        #expect(id != nil)

        var drawn = vm.printSelection.annotations(forKey: key).first
        #expect(drawn?.kind == .length)
        #expect(drawn?.text == "256.0 px")

        // Calibrated image with 0.5 mm x 0.5 mm pixel spacing -> 256 px * 0.5 mm/px = 128.0 mm
        var ds = DataSet()
        ds.setString("0.5\\0.5", for: .pixelSpacing, vr: .DS)
        vm.dicomFile = DICOMFile.create(dataSet: ds)

        if let id {
            vm.moveDrawnLengthEnd(id, isEnd: true, to: PrintOverlayPoint(x: 0.75, y: 0.5))
        }
        drawn = vm.printSelection.annotations(forKey: key).first
        #expect(drawn?.text == "128.0 mm")

        // Moving endpoint to 0.5, 0.5 (128 px * 0.5 mm/px = 64.0 mm)
        if let id {
            vm.moveDrawnLengthEnd(id, isEnd: true, to: PrintOverlayPoint(x: 0.5, y: 0.5))
        }
        drawn = vm.printSelection.annotations(forKey: key).first
        #expect(drawn?.text == "64.0 mm")
    }
}
