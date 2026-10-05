// ViewerAnnotationTests.swift
// DICOMStudioTests
//
// The reading annotations the viewer draws in a viewport's corners: what the
// file says, what the viewport says, and which edge the patient's left is on.

import Testing
@testable import DICOMStudio
import DICOMCore
import DICOMKit
import Foundation

@Suite("Viewer Annotation Text Tests")
struct ViewerAnnotationTextTests {

    private func dataSet(_ values: [(UInt16, UInt16, String, VR)]) -> DataSet {
        DataSet(elements: values.map { group, element, value, vr in
            // DICOM string values are even-length, padded with a space.
            let padded = value.count % 2 == 0 ? value : value + " "
            let data = Data(padded.utf8)
            return DataElement(
                tag: Tag(group: group, element: element),
                vr: vr,
                length: UInt32(data.count),
                valueData: data)
        })
    }

    private func uint16Element(_ group: UInt16, _ element: UInt16, _ value: UInt16) -> DataElement {
        var raw = value.littleEndian
        let data = Data(bytes: &raw, count: 2)
        return DataElement(
            tag: Tag(group: group, element: element),
            vr: .US,
            length: 2,
            valueData: data)
    }

    @Test("An MR file annotates who, what, how and when")
    func testMRAnnotations() {
        var set = dataSet([
            (0x0010, 0x0010, "JAGARAJ^ANTONY", .PN),
            (0x0010, 0x0020, "638145", .LO),
            (0x0010, 0x1010, "066Y", .AS),
            (0x0008, 0x1030, "C-Spine New C Spine", .LO),
            (0x0008, 0x103E, "t1_tse_sag_384", .LO),
            (0x0020, 0x0011, "9", .IS),
            (0x0008, 0x0060, "MR", .CS),
            (0x0018, 0x0081, "11", .DS),
            (0x0018, 0x0080, "781", .DS),
            (0x0018, 0x0087, "1.5", .DS),
            (0x0018, 0x0050, "3.0", .DS),
            (0x0020, 0x1041, "-6.97", .DS),
            (0x0008, 0x0022, "20260516", .DA),
            (0x0008, 0x0032, "142500", .TM),
            (0x0028, 0x1050, "476", .DS),
            (0x0028, 0x1051, "1036", .DS)
        ])
        set[Tag(group: 0x0028, element: 0x0010)] = uint16Element(0x0028, 0x0010, 384)
        set[Tag(group: 0x0028, element: 0x0011)] = uint16Element(0x0028, 0x0011, 384)

        let text = ViewerAnnotationText.make(
            from: set, transferSyntaxUID: "1.2.840.10008.1.2.1")

        #expect(text.patientLine.contains("ANTONY JAGARAJ"))
        #expect(text.patientLine.contains("638145"))
        #expect(text.patientLine.contains("(66 y)"), "the age reads as a qualifier, not an ID")
        #expect(text.studyLine == "C-Spine New C Spine")
        #expect(text.seriesNumberLine == "9")
        #expect(text.imageSizeLine == "Image size: 384 x 384")
        #expect(text.compressionLine == "Uncompressed")
        #expect(text.geometryLine == "Thickness: 3.00 mm",
                "the slice location is not part of the block")
        #expect(text.dateTimeLine.contains("2026-05-16"))
        #expect(text.fileWindowCenter == 476)
        #expect(text.fileWindowWidth == 1036)
        #expect(!text.isEmpty)
    }

    @Test("The technique the file records is not drawn over the picture")
    func testAcquisitionTechniqueIsNotAnnotated() {
        let text = ViewerAnnotationText.make(from: dataSet([
            (0x0008, 0x0060, "MR", .CS),
            (0x0018, 0x0081, "11", .DS),
            (0x0018, 0x0080, "781", .DS),
            (0x0018, 0x0087, "1.5", .DS),
            (0x0018, 0x0050, "3.0", .DS)
        ]), transferSyntaxUID: "1.2.840.10008.1.2.1")

        // Only the thickness survives from this set: TE/TR and the field
        // strength are read from the header, not from the corner.
        #expect(text.geometryLine == "Thickness: 3.00 mm")
    }

    @Test("A compressed file says which codec its pixels went through")
    func testCompressionLine() {
        #expect(ViewerAnnotationText.compressionLine(for: "1.2.840.10008.1.2") == "Uncompressed")
        #expect(ViewerAnnotationText.compressionLine(for: "1.2.840.10008.1.2.1") == "Uncompressed")
        #expect(ViewerAnnotationText.compressionLine(for: "1.2.840.10008.1.2.2") == "Uncompressed")
        // PS3.5 2026a A.4.11: encapsulated, but the frames are uncompressed pixel data.
        #expect(ViewerAnnotationText.compressionLine(for: "1.2.840.10008.1.2.1.98") == "Uncompressed")
        #expect(ViewerAnnotationText.compressionLine(for: "1.2.840.10008.1.2.1.99") == "Uncompressed")
        #expect(ViewerAnnotationText.compressionLine(for: "1.2.840.10008.1.2.4.91")
                == "JPEG 2000", "a lossy codec must be visible to the reader")
        #expect(ViewerAnnotationText.compressionLine(for: "1.2.840.10008.1.2.4.201")
                == "HTJ2K Lossless Only", "HTJ2K had no label and showed the bare UID")
        #expect(ViewerAnnotationText.compressionLine(for: "").isEmpty)
    }

    @Test("A de-identified file carries fewer lines rather than labelled blanks")
    func testMinimalFile() {
        let text = ViewerAnnotationText.make(from: DataSet(), transferSyntaxUID: "")
        #expect(text.isEmpty)
        #expect(text.geometryLine.isEmpty)
        #expect(text.orientation == nil)
    }

    @Test("The image's identity is carried alongside its drawn lines")
    func testSOPInstanceUIDIsCarried() {
        // The tile grid's saved-views badge asks "are there presentation states
        // for *this* image", and the only header read a tile's file gets is the
        // one that produced this value. Losing the UID here would mean either a
        // second decode per tile or a badge that cannot be drawn at all.
        let text = ViewerAnnotationText.make(
            from: dataSet([(0x0008, 0x0018, "1.2.3.4.5", .UI)]),
            transferSyntaxUID: "")
        #expect(text.sopInstanceUID == "1.2.3.4.5")
    }

    @Test("A file with no identity offers none rather than an empty one")
    func testMissingSOPInstanceUID() {
        // `nil` and `""` mean different things to the badge: no UID means the
        // question cannot be asked, whereas an empty string would be asked and
        // would match nothing, quietly reporting "no saved views" for an image
        // that may well have some.
        let text = ViewerAnnotationText.make(from: DataSet(), transferSyntaxUID: "")
        #expect(text.sopInstanceUID == nil)
    }

    @Test("Ages shorten to the corner's form")
    func testShortAge() {
        #expect(ViewerAnnotationText.shortAge("066Y") == "66 y")
        #expect(ViewerAnnotationText.shortAge("009M") == "9 m")
        #expect(ViewerAnnotationText.shortAge("nonsense") == "nonsense")
    }
}

@Suite("Viewer Orientation Label Tests")
struct ViewerOrientationLabelTests {

    /// Row cosine +x (patient left), column cosine +y (posterior) — an axial slice.
    private let axial = "1\\0\\0\\0\\1\\0"

    @Test("An axial slice puts the patient's left on the right of the picture")
    func testAxialEdges() {
        let labels = ViewerOrientationLabels.make(fromImageOrientationPatient: axial)
        #expect(labels?.right == "L")
        #expect(labels?.left == "R")
        #expect(labels?.top == "A")
        #expect(labels?.bottom == "P")
    }

    @Test("A sagittal slice reads head-up, front-left")
    func testSagittalEdges() {
        // Row +y (posterior), column −z (inferior).
        let labels = ViewerOrientationLabels.make(fromImageOrientationPatient: "0\\1\\0\\0\\0\\-1")
        #expect(labels?.right == "P")
        #expect(labels?.left == "A")
        // PS3.3 2026a C.7.6.1.1.1 Patient Orientation letters: H (head), F (foot).
        #expect(labels?.top == "H")
        #expect(labels?.bottom == "F")
    }

    @Test("An oblique direction names both axes it leans along")
    func testObliqueLetters() {
        let letters = ViewerOrientationLabels.letters(for: [0.0, -0.8, 0.6])
        #expect(letters == "AH", "strongest axis first")
    }

    @Test("A file with no orientation gets no letters rather than wrong ones")
    func testMissingOrientation() {
        #expect(ViewerOrientationLabels.make(fromImageOrientationPatient: nil) == nil)
        #expect(ViewerOrientationLabels.make(fromImageOrientationPatient: "1\\0\\0") == nil)
    }

    @Test("Rotating the tile moves the letters with the picture")
    func testRotation() {
        let labels = ViewerOrientationLabels.make(fromImageOrientationPatient: axial)!
        let turned = labels.transformed(
            rotationDegrees: 90, flipHorizontal: false, flipVertical: false)

        // A clockwise quarter turn sends the left edge to the top.
        #expect(turned.top == "R")
        #expect(turned.right == "A")
        #expect(turned.bottom == "L")
        #expect(turned.left == "P")
    }

    @Test("Flipping swaps the sides it flips, and only those")
    func testFlips() {
        let labels = ViewerOrientationLabels.make(fromImageOrientationPatient: axial)!

        let mirrored = labels.transformed(
            rotationDegrees: 0, flipHorizontal: true, flipVertical: false)
        #expect(mirrored.left == "L")
        #expect(mirrored.right == "R")
        #expect(mirrored.top == "A")

        let upended = labels.transformed(
            rotationDegrees: 0, flipHorizontal: false, flipVertical: true)
        #expect(upended.top == "P")
        #expect(upended.bottom == "A")
        #expect(upended.left == "R")
    }

    @Test("A full turn is no turn, and a negative turn is its positive equal")
    func testRotationNormalisation() {
        let labels = ViewerOrientationLabels.make(fromImageOrientationPatient: axial)!
        let full = labels.transformed(
            rotationDegrees: 360, flipHorizontal: false, flipVertical: false)
        #expect(full == labels)

        let negative = labels.transformed(
            rotationDegrees: -90, flipHorizontal: false, flipVertical: false)
        let equivalent = labels.transformed(
            rotationDegrees: 270, flipHorizontal: false, flipVertical: false)
        #expect(negative == equivalent)
    }
}

@Suite("Viewer Hover Geometry Tests")
struct ViewerHoverGeometryTests {

    /// The mapping under test, with the arrangement supplied per case.
    private func pixel(
        at point: CGPoint,
        view: CGSize = CGSize(width: 100, height: 100),
        image: (Int, Int) = (100, 100),
        zoom: Double = 1,
        pan: (Double, Double) = (0, 0),
        rotation: Double = 0,
        flipHorizontal: Bool = false,
        flipVertical: Bool = false,
        order: ViewerTransformOrder = .panBeforeRotation
    ) -> (column: Int, row: Int)? {
        ViewerHoverGeometry.imagePixel(
            atViewPoint: point,
            viewSize: view,
            imageWidth: image.0,
            imageHeight: image.1,
            zoom: zoom,
            panX: pan.0,
            panY: pan.1,
            rotationDegrees: rotation,
            flipHorizontal: flipHorizontal,
            flipVertical: flipVertical,
            order: order)
    }

    @Test("An untransformed image maps point for point")
    func testIdentity() {
        #expect(pixel(at: CGPoint(x: 0.5, y: 0.5))! == (0, 0))
        #expect(pixel(at: CGPoint(x: 50.5, y: 25.5))! == (50, 25))
        #expect(pixel(at: CGPoint(x: 99.5, y: 99.5))! == (99, 99))
    }

    @Test("A pixel is the square between its edges, not the point nearest its centre")
    func testPixelCoversItsSquare() {
        // A 100 px image in a 200 pt view: each pixel is two points across.
        let view = CGSize(width: 200, height: 200)
        #expect(pixel(at: CGPoint(x: 0.1, y: 0.1), view: view)! == (0, 0))
        #expect(pixel(at: CGPoint(x: 1.9, y: 1.9), view: view)! == (0, 0))
        #expect(pixel(at: CGPoint(x: 2.1, y: 2.1), view: view)! == (1, 1))
    }

    @Test("The margin an aspect-fitted image leaves is not part of the image")
    func testLetterbox() {
        // 100×50 image in a 200×200 view fits to 200×100, centred: rows 50…150.
        let view = CGSize(width: 200, height: 200)
        #expect(pixel(at: CGPoint(x: 100, y: 10), view: view, image: (100, 50)) == nil)
        #expect(pixel(at: CGPoint(x: 100, y: 190), view: view, image: (100, 50)) == nil)
        #expect(pixel(at: CGPoint(x: 100, y: 100), view: view, image: (100, 50))! == (50, 25))
        #expect(pixel(at: CGPoint(x: 1, y: 51), view: view, image: (100, 50))! == (0, 0))
    }

    @Test("Zooming in narrows what the viewport covers, about its centre")
    func testZoom() {
        // At 2×, the centre is unmoved and each point covers half a pixel.
        #expect(pixel(at: CGPoint(x: 50, y: 50), zoom: 2)! == (50, 50))
        #expect(pixel(at: CGPoint(x: 30, y: 50), zoom: 2)! == (40, 50))
        // The corners of the view are now off the picture.
        #expect(pixel(at: CGPoint(x: 0.5, y: 0.5), zoom: 2)! == (25, 25))
    }

    @Test("Panning moves the picture, so the viewport moves the other way over it")
    func testPan() {
        // Dragging the image 10 pt right puts image column 40 under view x 50.
        #expect(pixel(at: CGPoint(x: 50, y: 50), pan: (10, 0))! == (40, 50))
        #expect(pixel(at: CGPoint(x: 50, y: 50), pan: (0, -20))! == (50, 70))
    }

    @Test("A quarter turn clockwise puts the image's left edge along the top")
    func testRotation() {
        // Points are taken at pixel centres: the .5 offsets are the middle of
        // the outermost pixel, not the edge two pixels share.
        let top = pixel(at: CGPoint(x: 50.5, y: 0.5), rotation: 90)!
        #expect(top.column == 0, "the left column is now at the top")
        // Mid-height: the centre of an even-sized image falls between two rows,
        // so either side of the centre line is the same point.
        #expect(top.row == 49 || top.row == 50)

        let right = pixel(at: CGPoint(x: 99.5, y: 50.5), rotation: 90)!
        #expect(right.row == 0, "the top row is now on the right")
    }

    @Test("Mirroring swaps the side a point comes from")
    func testFlips() {
        // Pixel centres again: column 10's centre mirrors onto column 89's.
        #expect(pixel(at: CGPoint(x: 10.5, y: 50.5), flipHorizontal: true)!.column == 89)
        #expect(pixel(at: CGPoint(x: 50.5, y: 10.5), flipVertical: true)!.row == 89)
        #expect(pixel(at: CGPoint(x: 10.5, y: 50.5), flipHorizontal: true)!.row == 50,
                "a horizontal mirror leaves the row alone")
    }

    @Test("The two display paths pan on opposite sides of the rotation")
    func testTransformOrderMatters() {
        let point = CGPoint(x: 50, y: 50)
        let before = pixel(at: point, pan: (20, 0), rotation: 90, order: .panBeforeRotation)!
        let after = pixel(at: point, pan: (20, 0), rotation: 90, order: .panAfterRotation)!
        #expect(before != after, "which one is right depends on which path drew the picture")

        // Unrotated, the two compositions are the same transform.
        let unrotatedBefore = pixel(at: point, pan: (20, 0), order: .panBeforeRotation)!
        let unrotatedAfter = pixel(at: point, pan: (20, 0), order: .panAfterRotation)!
        #expect(unrotatedBefore == unrotatedAfter)
    }

    @Test("A point off the picture, or a viewport with no size, has no pixel")
    func testNoPixel() {
        #expect(pixel(at: CGPoint(x: -5, y: 50)) == nil)
        #expect(pixel(at: CGPoint(x: 50, y: 120)) == nil)
        #expect(pixel(at: CGPoint(x: 50, y: 50), view: .zero) == nil)
        #expect(pixel(at: CGPoint(x: 50, y: 50), image: (0, 0)) == nil)
        #expect(pixel(at: CGPoint(x: 50, y: 50), zoom: 0) == nil)
    }
}

@Suite("Viewer Image Plane Tests")
struct ViewerImagePlaneTests {

    private let plane = ViewerImagePlane(
        origin: [-150, -75, -430],
        rowDirection: [1, 0, 0],
        columnDirection: [0, 1, 0],
        rowSpacing: 0.5,
        columnSpacing: 0.75)

    @Test("The first pixel is where the file says the image starts")
    func testOrigin() {
        let point = plane.patientCoordinate(column: 0, row: 0)
        #expect(point.x == -150)
        #expect(point.y == -75)
        #expect(point.z == -430)
    }

    @Test("Columns step along the row direction, rows down the column direction")
    func testSpacingAxes() {
        let point = plane.patientCoordinate(column: 100, row: 40)
        // Column spacing is the distance between columns: 100 × 0.75.
        #expect(abs(point.x - (-150 + 75)) < 1e-9)
        // Row spacing is the distance between rows: 40 × 0.5.
        #expect(abs(point.y - (-75 + 20)) < 1e-9)
        #expect(point.z == -430)
    }

    @Test("An oblique plane moves along both of its directions")
    func testOblique() {
        let oblique = ViewerImagePlane(
            origin: [0, 0, 0],
            rowDirection: [0, 1, 0],
            columnDirection: [0, 0, -1],
            rowSpacing: 2,
            columnSpacing: 1)
        let point = oblique.patientCoordinate(column: 10, row: 5)
        #expect(point.x == 0)
        #expect(point.y == 10)
        #expect(point.z == -10)
    }

    @Test("A file that does not place its pixels produces no plane")
    func testMissingGeometry() {
        #expect(ViewerImagePlane.make(from: DataSet()) == nil)
    }
}

@Suite("Viewer Cursor Readout Tests")
struct ViewerCursorReadoutTests {

    @Test("The pixel address and its value read as one line")
    func testPixelText() {
        let readout = ViewerCursorReadout(
            column: 389, row: 128, valueText: "Value: 41 HU")
        #expect(readout.pixelText == "X: 389 px  Y: 128 px  Value: 41 HU")
    }

    @Test("A value that cannot be read leaves the address standing alone")
    func testUnreadableValue() {
        let readout = ViewerCursorReadout(column: 4, row: 9)
        #expect(readout.pixelText == "X: 4 px  Y: 9 px")
        #expect(readout.patientText.isEmpty)
    }
}

@MainActor
@Suite("Viewer Annotation Position Source Tests")
struct ViewerAnnotationPositionSourceTests {

    private func seriesViewModel() -> ImageViewerViewModel {
        let viewModel = ImageViewerViewModel()
        viewModel.filePath = "/s1-a.dcm"
        viewModel.seriesFiles = ["/s1-a.dcm", "/s1-b.dcm", "/s1-c.dcm"]
        viewModel.viewContentWidth = 800
        viewModel.viewContentHeight = 800
        return viewModel
    }

    @Test("The live viewport's Im: number follows navigation")
    @available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
    func testLivePositionFollowsNavigation() {
        let viewModel = seriesViewModel()
        let size = CGSize(width: 800, height: 800)

        #expect(viewModel.annotationViewportState(viewSize: size).imagePosition == 1)

        viewModel.currentFileIndex = 2
        #expect(viewModel.annotationViewportState(viewSize: size).imagePosition == 3,
                "the number the reader is about to change must track the image on screen")
        #expect(viewModel.annotationViewportState(viewSize: size).imageCount == 3)
    }

    @Test("A cell's Im: number is only as fresh as its last capture")
    @available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
    func testCellPositionLagsUntilCaptured() {
        // This is why the focused tile's annotation state is built from the view
        // model rather than from its stored cell: navigation moves the live
        // index and leaves the cell where it was hung, so a grid reading its
        // cells showed "Im: 1/33" for the whole stack. See `viewportState(for:)`
        // in `ViewerTileGridView`.
        let viewModel = seriesViewModel()
        viewModel.applyLayout(ViewerTileLayout(rows: 1, columns: 2))
        viewModel.focusCell(0)

        viewModel.currentFileIndex = 2

        let cell = viewModel.cells[0]
        #expect(viewModel.annotationViewportState(for: cell).imagePosition == 1,
                "the un-captured cell is expected to lag — the view must not read it")

        viewModel.captureFocusedCell()
        #expect(viewModel.annotationViewportState(for: viewModel.cells[0]).imagePosition == 3)
    }
}

@Suite("Viewer Annotation Corner Tests")
struct ViewerAnnotationCornerTests {

    private let text = ViewerAnnotationText(
        patientLine: "ANTONY JAGARAJ 638145 (66 y)",
        studyLine: "C-Spine New C Spine",
        seriesNumberLine: "9",
        imageSizeLine: "Image size: 384 x 384",
        compressionLine: "Uncompressed",
        geometryLine: "Thickness: 3.00 mm",
        dateTimeLine: "2026-05-16 14:25:00",
        orientation: ViewerOrientationLabels(left: "A", right: "P", top: "H", bottom: "F"),
        fileWindowCenter: 476,
        fileWindowWidth: 1036)

    private func state(
        window: (Double, Double)? = (476, 1036),
        zoom: Double = 1.06,
        rotation: Double = 0
    ) -> ViewerAnnotationViewportState {
        ViewerAnnotationViewportState(
            viewSize: CGSize(width: 602, height: 407),
            windowCenter: window?.0,
            windowWidth: window?.1,
            zoom: zoom,
            rotationDegrees: rotation,
            imagePosition: 1,
            imageCount: 17)
    }

    @Test("A full-size viewport carries the whole block, corner by corner")
    func testFullDetail() {
        let corners = ViewerAnnotationCorners.make(
            text: text, state: state(), detail: .full)

        #expect(corners.topLeft == [
            "Image size: 384 x 384", "View size: 602 x 407", "WL: 476  WW: 1036"
        ])
        #expect(corners.topRight == [
            "ANTONY JAGARAJ 638145 (66 y)", "C-Spine New C Spine", "9"
        ])
        #expect(corners.bottomLeft == [
            "Zoom: 106%  Angle: 0", "Im: 1/17", "Uncompressed", "Thickness: 3.00 mm"
        ])
        #expect(corners.bottomRight == ["2026-05-16 14:25:00"])
        #expect(!corners.isEmpty)
    }

    @Test("A small tile keeps who and where, and drops the rest")
    func testDetailLevels() {
        #expect(ViewerAnnotationCorners.Detail.forViewport(CGSize(width: 900, height: 700)) == .full)
        #expect(ViewerAnnotationCorners.Detail.forViewport(CGSize(width: 600, height: 240)) == .reduced)
        #expect(ViewerAnnotationCorners.Detail.forViewport(CGSize(width: 300, height: 150)) == .minimal)

        let minimal = ViewerAnnotationCorners.make(
            text: text, state: state(), detail: .minimal)
        #expect(minimal.topRight == ["ANTONY JAGARAJ 638145 (66 y)"])
        #expect(minimal.bottomLeft == ["Im: 1/17"])
        #expect(minimal.topLeft.isEmpty)
        #expect(minimal.bottomRight.isEmpty)
    }

    @Test("A tile the user has not windowed states the window the file asks for")
    func testWindowFallsBackToTheFile() {
        let corners = ViewerAnnotationCorners.make(
            text: text, state: state(window: nil), detail: .full)
        #expect(corners.topLeft.contains("WL: 476  WW: 1036"))
    }

    @Test("A window neither the tile nor the file states is left unsaid")
    func testWindowUnknown() {
        let windowless = ViewerAnnotationText(patientLine: "ANON")
        let corners = ViewerAnnotationCorners.make(
            text: windowless, state: state(window: nil), detail: .full)
        #expect(!corners.topLeft.contains { $0.hasPrefix("WL:") })
    }

    @Test("The angle is stated even at zero, and normalised past a full turn")
    func testZoomText() {
        #expect(ViewerAnnotationCorners.zoomText(zoom: 1, rotationDegrees: 0)
                == "Zoom: 100%  Angle: 0")
        #expect(ViewerAnnotationCorners.zoomText(zoom: 2.5, rotationDegrees: 450)
                == "Zoom: 250%  Angle: 90")
        #expect(ViewerAnnotationCorners.zoomText(zoom: 1, rotationDegrees: -90)
                == "Zoom: 100%  Angle: 270")
    }

    @Test("A single image says its position without inventing a series length")
    func testImagePositionText() {
        #expect(ViewerAnnotationCorners.imagePositionText(position: 3, count: 12) == "Im: 3/12")
        #expect(ViewerAnnotationCorners.imagePositionText(position: 1, count: nil) == "Im: 1")
        #expect(ViewerAnnotationCorners.imagePositionText(position: nil, count: 12).isEmpty)
    }

    @Test("The cursor's pixel and patient coordinates join the top-left block")
    func testCursorLines() {
        var withCursor = state()
        withCursor.cursor = ViewerCursorReadout(
            column: 389, row: 128,
            valueText: "Value: 41 HU",
            patientText: "X: 169.58 mm  Y: 58.73 mm  Z: -430.01 mm")

        let corners = ViewerAnnotationCorners.make(
            text: text, state: withCursor, detail: .full)
        #expect(corners.topLeft.contains("X: 389 px  Y: 128 px  Value: 41 HU"))
        #expect(corners.topLeft.contains("X: 169.58 mm  Y: 58.73 mm  Z: -430.01 mm"))
        #expect(corners.topLeft.count == 5, "under the window, not instead of it")

        // A smaller tile keeps the value and drops the millimetres.
        let reduced = ViewerAnnotationCorners.make(
            text: text, state: withCursor, detail: .reduced)
        #expect(reduced.topLeft == ["WL: 476  WW: 1036", "X: 389 px  Y: 128 px  Value: 41 HU"])
    }

    @Test("A pointer that is not over the picture adds no lines at all")
    func testNoCursorLines() {
        let corners = ViewerAnnotationCorners.make(
            text: text, state: state(), detail: .full)
        #expect(corners.topLeft.count == 3)
        #expect(!corners.topLeft.contains { $0.contains(" px") })
    }

    @Test("The edge letters follow the viewport's rotation")
    func testOrientationFollowsRotation() {
        let corners = ViewerAnnotationCorners.make(
            text: text, state: state(rotation: 90), detail: .full)
        #expect(corners.orientation?.top == "A", "the left edge turns to the top")
    }

    @Test("A file with nothing to say draws nothing")
    func testEmpty() {
        let corners = ViewerAnnotationCorners.make(
            text: ViewerAnnotationText(),
            state: ViewerAnnotationViewportState(),
            detail: .minimal)
        #expect(corners.isEmpty)
    }
}
