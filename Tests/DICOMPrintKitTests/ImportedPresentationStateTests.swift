//
// ImportedPresentationStateTests.swift
// DICOMPrintKit
//
// A presentation state written by another viewer, taken into the store and
// carried through to the film.
//
// The fixture is what Weasis writes when a reader saves a session: one GSPS
// for a series, with a ruler and its "20.0 mm" label on one image, a circle
// ROI with an anchored label on another, a rectangular shutter, and its own
// rescale. These tests cover the whole road that object travels here —
// adoption into the store, the per-image drawings it yields, the shapes'
// pixels on the burned frame — and the two properties that keep the road
// safe to drive twice: adoption is idempotent, and every imported drawing is
// locked.
//

import XCTest
import DICOMCore
import DICOMKit
@testable import DICOMPrintKit
import DICOMNetwork

final class ImportedPresentationStateTests: XCTestCase {

    private var root: URL!
    private var studyFolder: URL!
    private var store: PresentationStateStore!

    private let studyUID = "1.2.3.4.5"
    private let seriesUID = "1.2.3.4.5.6"
    private let imageA = "1.2.3.4.5.6.1"
    private let imageB = "1.2.3.4.5.6.2"
    private let ctSOPClass = "1.2.840.10008.5.1.4.1.1.2"

    private var images: [String: PresentationStateStore.AdoptableImage] {
        [imageA: .init(sopInstanceUID: imageA, columns: 512, rows: 512),
         imageB: .init(sopInstanceUID: imageB, columns: 512, rows: 512, numberOfFrames: 3)]
    }

    override func setUpWithError() throws {
        try super.setUpWithError()
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("ImportedPresentationStateTests-\(UUID().uuidString)")
        root = base.appendingPathComponent("store")
        studyFolder = base.appendingPathComponent("study")
        try FileManager.default.createDirectory(at: studyFolder, withIntermediateDirectories: true)
        store = PresentationStateStore(root: root)
    }

    override func tearDownWithError() throws {
        let base = root.deletingLastPathComponent()
        if FileManager.default.fileExists(atPath: base.path) {
            try FileManager.default.removeItem(at: base)
        }
        try super.tearDownWithError()
    }

    // MARK: - Fixture: a Weasis-style GSPS

    private func weasisState(sopInstanceUID: String = "1.2.3.4.5.99.1") -> GrayscalePresentationState {
        let refA = ReferencedImage(sopClassUID: ctSOPClass, sopInstanceUID: imageA)
        let refB = ReferencedImage(sopClassUID: ctSOPClass, sopInstanceUID: imageB,
                                   referencedFrameNumbers: [2])
        return GrayscalePresentationState(
            sopInstanceUID: sopInstanceUID,
            instanceNumber: 1,
            presentationLabel: "Weasis measurements",
            presentationDescription: "Weasis measurements",
            presentationCreationDate: DICOMDate(year: 2026, month: 8, day: 30),
            referencedSeries: [ReferencedSeries(
                seriesInstanceUID: seriesUID,
                referencedImages: [
                    ReferencedImage(sopClassUID: ctSOPClass, sopInstanceUID: imageA),
                    ReferencedImage(sopClassUID: ctSOPClass, sopInstanceUID: imageB)])],
            modalityLUT: .rescale(slope: 2, intercept: -1000, type: "HU"),
            voiLUT: .window(center: 40, width: 400, explanation: nil, function: .linear),
            graphicLayers: [GraphicLayer(
                name: "MEASURE", order: 1,
                recommendedRGBValue: (red: 0, green: 65535, blue: 0))],
            graphicAnnotations: [
                GraphicAnnotation(
                    layer: "MEASURE",
                    referencedImages: [refA],
                    graphicObjects: [GraphicObject(
                        type: .polyline, data: [100, 100, 300, 100], filled: false, units: .pixel)],
                    textObjects: [TextObject(
                        text: "20.0 mm",
                        boundingBoxTopLeft: (column: 310, row: 90),
                        boundingBoxBottomRight: (column: 380, row: 110),
                        anchorPoint: nil, anchorPointVisible: false,
                        boundingBoxUnits: .pixel, anchorPointUnits: .pixel)]),
                GraphicAnnotation(
                    layer: "MEASURE",
                    referencedImages: [refB],
                    graphicObjects: [GraphicObject(
                        type: .circle, data: [256, 256, 300, 256], filled: false, units: .pixel)],
                    textObjects: [TextObject(
                        text: "Area 61.2 mm²",
                        boundingBoxTopLeft: (column: 320, row: 200),
                        boundingBoxBottomRight: (column: 420, row: 220),
                        anchorPoint: (column: 256, row: 256), anchorPointVisible: true,
                        boundingBoxUnits: .pixel, anchorPointUnits: .pixel)])
            ],
            shutters: [.rectangular(left: 50, right: 462, top: 50, bottom: 462, presentationValue: 0)])
    }

    /// Writes the fixture into the study folder as another viewer would, and
    /// returns its URL.
    @discardableResult
    private func writeWeasisObject(
        named name: String = "pr.dcm",
        sopClassUID: String = GrayscalePresentationStateBuilder.sopClassUID,
        studyInstanceUID: String? = nil
    ) throws -> URL {
        let state = weasisState()
        var dataSet = GrayscalePresentationStateBuilder().buildDataSet(
            from: state,
            patient: PresentationStatePatientContext(
                patientName: "DOE^JANE", patientID: "12345",
                studyInstanceUID: studyInstanceUID ?? studyUID),
            seriesInstanceUID: "1.2.3.4.5.99",
            seriesNumber: 99)
        // The builder writes the Display Shutter module from the state (C.7.6.11);
        // the Modality LUT the fixture states the way the standard spells it (C.11.1).
        dataSet.setString("2", for: .rescaleSlope, vr: .DS)
        dataSet.setString("-1000", for: .rescaleIntercept, vr: .DS)
        dataSet.setString(sopClassUID, for: .sopClassUID, vr: .UI)

        let url = studyFolder.appendingPathComponent(name)
        let file = DICOMFile.create(
            dataSet: dataSet,
            sopClassUID: sopClassUID,
            sopInstanceUID: state.sopInstanceUID,
            transferSyntaxUID: PresentationStateStore.transferSyntaxUID)
        try file.write().write(to: url)
        return url
    }

    // MARK: - Adoption

    func test_adopt_takesTheStudysObjectIntoTheStore() throws {
        let url = try writeWeasisObject()

        let result = store.adopt(
            presentationStateFiles: [url], studyInstanceUID: studyUID, images: images)

        XCTAssertEqual(result.adopted.count, 1)
        XCTAssertEqual(result.skipped, 0)
        let views = store.views(forStudy: studyUID)
        XCTAssertEqual(views.count, 1)
        let view = try XCTUnwrap(views.first)
        XCTAssertEqual(view.label, "Weasis measurements")
        XCTAssertTrue(view.isImported)
        XCTAssertTrue(view.covers(image: imageA))
        XCTAssertTrue(view.covers(image: imageB))
    }

    func test_adopt_isIdempotent() throws {
        let url = try writeWeasisObject()
        _ = store.adopt(presentationStateFiles: [url], studyInstanceUID: studyUID, images: images)

        let again = store.adopt(
            presentationStateFiles: [url], studyInstanceUID: studyUID, images: images)

        XCTAssertEqual(again.adopted.count, 0)
        XCTAssertEqual(again.alreadyPresent, 1)
        XCTAssertEqual(store.views(forStudy: studyUID).count, 1)
    }

    func test_aDeletedImportedViewIsNotAdoptedBack() throws {
        let url = try writeWeasisObject()
        _ = store.adopt(presentationStateFiles: [url], studyInstanceUID: studyUID, images: images)

        try store.deleteView(label: "Weasis measurements", studyInstanceUID: studyUID)
        let again = store.adopt(
            presentationStateFiles: [url], studyInstanceUID: studyUID, images: images)

        XCTAssertEqual(again.adopted.count, 0)
        XCTAssertTrue(store.views(forStudy: studyUID).isEmpty,
                      "the reader took it off; the next open must not put it back")
    }

    func test_adopt_skipsAnObjectDescribingNoImageTheStudyHas() throws {
        let url = try writeWeasisObject()
        let strangers: [String: PresentationStateStore.AdoptableImage] = [
            "9.9.9": .init(sopInstanceUID: "9.9.9", columns: 512, rows: 512)]

        let result = store.adopt(
            presentationStateFiles: [url], studyInstanceUID: studyUID, images: strangers)

        XCTAssertEqual(result.adopted.count, 0)
        XCTAssertEqual(result.skipped, 1)
        XCTAssertTrue(store.views(forStudy: studyUID).isEmpty)
    }

    func test_adopt_skipsAnObjectOfAnotherStudy() throws {
        let url = try writeWeasisObject(studyInstanceUID: "7.7.7")

        let result = store.adopt(
            presentationStateFiles: [url], studyInstanceUID: studyUID, images: images)

        XCTAssertEqual(result.skipped, 1)
        XCTAssertTrue(store.views(forStudy: studyUID).isEmpty)
    }

    func test_adopt_ignoresFilesThatAreNotPresentationStates() throws {
        let image = studyFolder.appendingPathComponent("image.dcm")
        let file = DICOMFile.create(
            dataSet: DataSet(elements: [
                .string(tag: .sopClassUID, vr: .UI, value: ctSOPClass),
                .string(tag: .sopInstanceUID, vr: .UI, value: imageA)]),
            sopClassUID: ctSOPClass, sopInstanceUID: imageA)
        try file.write().write(to: image)

        let result = store.adopt(
            presentationStateFiles: [image], studyInstanceUID: studyUID, images: images)

        XCTAssertEqual(result.adopted.count, 0)
        XCTAssertEqual(result.skipped, 1)
    }

    func test_colorSoftcopyObjectIsReadAndAdopted() throws {
        let url = try writeWeasisObject(
            named: "csps.dcm", sopClassUID: "1.2.840.10008.5.1.4.1.1.11.2")

        let file = try DICOMFile.read(from: url)
        let parsed = try GrayscalePresentationStateParser().parse(dataSet: file.dataSet)
        XCTAssertEqual(parsed.sopClassUID, "1.2.840.10008.5.1.4.1.1.11.2")
        XCTAssertEqual(parsed.graphicAnnotations.count, 2)

        let result = store.adopt(
            presentationStateFiles: [url], studyInstanceUID: studyUID, images: images)
        XCTAssertEqual(result.adopted.count, 1)
        XCTAssertTrue(store.views(forStudy: studyUID).first?.isImported ?? false)
    }

    // MARK: - What the adopted object says

    private func adoptedState() throws -> StoredPresentationState {
        let url = try writeWeasisObject()
        _ = store.adopt(presentationStateFiles: [url], studyInstanceUID: studyUID, images: images)
        return try XCTUnwrap(store.views(forStudy: studyUID).first?.state(forImage: imageA))
    }

    func test_drawingsAreFiledPerImageAndFrame() throws {
        let stored = try adoptedState()

        let onA = stored.annotationsByFrame(forImage: imageA)
        XCTAssertEqual(Set(onA.keys), [0])
        let kindsA = onA[0]?.map(\.kind) ?? []
        XCTAssertEqual(kindsA, [.shutter, .polyline, .text],
                       "shutter first, then the ruler and its label")

        // Image B's item named frame 2; the shutter applies to every frame.
        let onB = stored.annotationsByFrame(forImage: imageB)
        XCTAssertEqual(Set(onB.keys), [0, 1, 2])
        XCTAssertEqual(onB[1]?.map(\.kind), [.shutter, .circle, .annotation])
        XCTAssertEqual(onB[0]?.map(\.kind), [.shutter])
        XCTAssertEqual(onB[2]?.map(\.kind), [.shutter])
    }

    func test_rulerKeepsItsGeometryColourAndLabel() throws {
        let stored = try adoptedState()
        let onA = try XCTUnwrap(stored.annotationsByFrame(forImage: imageA)[0])

        let ruler = try XCTUnwrap(onA.first { $0.kind == .polyline })
        XCTAssertEqual(ruler.points.count, 2)
        XCTAssertEqual(ruler.points[0].x, 100.0 / 512, accuracy: 1e-9)
        XCTAssertEqual(ruler.points[0].y, 100.0 / 512, accuracy: 1e-9)
        XCTAssertEqual(ruler.points[1].x, 300.0 / 512, accuracy: 1e-9)
        // The layer colour travels as CIELab (0070,0401), a 16-bit encoding (C.10.7.1.1)
        XCTAssertEqual(ruler.color.red, 0, accuracy: 0.01)
        XCTAssertEqual(ruler.color.green, 1, accuracy: 0.01)
        XCTAssertEqual(ruler.color.blue, 0, accuracy: 0.01)
        XCTAssertTrue(ruler.isLocked)

        let label = try XCTUnwrap(onA.first { $0.kind == .text })
        XCTAssertEqual(label.text, "20.0 mm")
        XCTAssertEqual(label.start.x, 310.0 / 512, accuracy: 1e-9)
        XCTAssertEqual(label.start.y, 90.0 / 512, accuracy: 1e-9)
        // The box was 20 rows tall on a 512-row image.
        XCTAssertEqual(label.scale, 20.0 / 512, accuracy: 1e-9)
        XCTAssertTrue(label.isLocked)
    }

    func test_anchoredLabelBecomesTheCombinedKind() throws {
        let stored = try adoptedState()
        let onB = try XCTUnwrap(stored.annotationsByFrame(forImage: imageB)[1])

        let label = try XCTUnwrap(onB.first { $0.kind == .annotation })
        XCTAssertEqual(label.text, "Area 61.2 mm²")
        XCTAssertEqual(label.end.x, 256.0 / 512, accuracy: 1e-9)
        XCTAssertEqual(label.end.y, 256.0 / 512, accuracy: 1e-9)
        XCTAssertTrue(label.hasArrow)
    }

    func test_shutterCarriesItsRegionAndValue() throws {
        let stored = try adoptedState()
        let shutter = try XCTUnwrap(
            stored.annotationsByFrame(forImage: imageA)[0]?.first { $0.kind == .shutter })

        XCTAssertEqual(shutter.points.count, 2)
        // Left edge 50 is a 1-based pixel position (PS3.3 Table C.7-17a) and
        // pixel 50 is open, so the open region starts at its left edge, 49.
        XCTAssertEqual(shutter.points[0].x, 49.0 / 512, accuracy: 1e-9)
        XCTAssertEqual(shutter.points[1].x, 462.0 / 512, accuracy: 1e-9)
        XCTAssertEqual(shutter.color, PrintOverlayColor(red: 0, green: 0, blue: 0))
    }

    func test_stateCarriesItsOwnRescaleForTheWindow() throws {
        let stored = try adoptedState()
        let restored = ViewerPresentationStateBridge.restore(
            stored.state, imageWidth: 512, imageHeight: 512,
            viewportWidth: 800, viewportHeight: 600)
        XCTAssertEqual(restored.rescaleSlope, 2)
        XCTAssertEqual(restored.rescaleIntercept, -1000)
        XCTAssertEqual(restored.windowCenter, 40)
    }

    // MARK: - On the film

    #if canImport(CoreGraphics)
    private func frame(width: Int = 512, height: Int = 512, fill: UInt8 = 128) -> PreparedPrintImage {
        PreparedPrintImage(
            descriptor: PrintImageData(
                pixelData: Data(repeating: fill, count: width * height),
                rows: UInt16(height), columns: UInt16(width),
                bitsAllocated: 8, bitsStored: 8, highBit: 7,
                samplesPerPixel: 1, pixelRepresentation: 0,
                photometricInterpretation: "MONOCHROME2"),
            sourcePath: "/a.dcm", frameIndex: 0)
    }

    private func pixel(_ image: PreparedPrintImage, x: Int, y: Int) -> UInt8 {
        image.descriptor.pixelData[y * Int(image.descriptor.columns) + x]
    }

    func test_rulerIsBurnedAlongItsLine() throws {
        let stored = try adoptedState()
        let overlays = try XCTUnwrap(stored.annotationsByFrame(forImage: imageA)[0])
            .filter { $0.kind == .polyline }

        let burned = ImageAnnotationBurner.burning(overlays: overlays, into: frame())

        XCTAssertNotEqual(pixel(burned, x: 200, y: 100), 128, "on the ruler")
        XCTAssertEqual(pixel(burned, x: 200, y: 300), 128, "well away from it")
        XCTAssertEqual(pixel(burned, x: 400, y: 100), 128, "past its end")
    }

    func test_shutterPaintsOutsideItsRegionOnly() throws {
        let stored = try adoptedState()
        let overlays = try XCTUnwrap(stored.annotationsByFrame(forImage: imageA)[0])
            .filter { $0.kind == .shutter }

        let burned = ImageAnnotationBurner.burning(overlays: overlays, into: frame())

        XCTAssertEqual(pixel(burned, x: 10, y: 10), 0, "outside the shutter: the presentation value")
        XCTAssertEqual(pixel(burned, x: 500, y: 256), 0)
        XCTAssertEqual(pixel(burned, x: 256, y: 256), 128, "inside: untouched")
    }

    func test_shutterIsBurnedUnderTheRuler() throws {
        // A ruler that runs out through the shutter's edge: its pixels beyond
        // the edge must still be there, which they are only if the shutter
        // was painted first.
        let ruler = PrintOverlayAnnotation(
            shape: .polyline,
            points: [PrintOverlayPoint(x: 0.5, y: 0.5), PrintOverlayPoint(x: 0.99, y: 0.5)],
            color: .white)
        let shutter = PrintOverlayAnnotation(
            shape: .shutter,
            points: [PrintOverlayPoint(x: 0.1, y: 0.1), PrintOverlayPoint(x: 0.9, y: 0.9)],
            color: PrintOverlayColor(red: 0, green: 0, blue: 0))

        // Handed in ruler-first on purpose: the burner orders them.
        let burned = ImageAnnotationBurner.burning(overlays: [ruler, shutter], into: frame())

        XCTAssertNotEqual(pixel(burned, x: 490, y: 256), 0, "the ruler survives past the edge")
        XCTAssertEqual(pixel(burned, x: 490, y: 100), 0, "the shutter is there beside it")
    }

    func test_circleIsBurnedAsARing() throws {
        let circle = PrintOverlayAnnotation(
            shape: .circle,
            points: [PrintOverlayPoint(x: 0.5, y: 0.5), PrintOverlayPoint(x: 0.7, y: 0.5)],
            color: .white)
        let burned = ImageAnnotationBurner.burning(overlays: [circle], into: frame())

        // Radius is 0.2 × 512 ≈ 102 px around (256,256).
        XCTAssertNotEqual(pixel(burned, x: 256 + 102, y: 256), 128, "on the ring, right")
        XCTAssertNotEqual(pixel(burned, x: 256, y: 256 - 102), 128, "on the ring, top")
        XCTAssertEqual(pixel(burned, x: 256, y: 256), 128, "the centre is untouched")
    }

    func test_rulerFollowsAQuarterTurn() throws {
        let ruler = PrintOverlayAnnotation(
            shape: .polyline,
            points: [PrintOverlayPoint(x: 0.2, y: 0.5), PrintOverlayPoint(x: 0.8, y: 0.5)],
            color: .white)
        let turned = PrintOverlayOrientation(
            presentation: ViewerPresentation(
                viewportWidth: 512, viewportHeight: 512, rotationDegrees: 90),
            imageWidth: 512, imageHeight: 512)

        let burned = ImageAnnotationBurner.burning(
            overlays: [ruler], into: frame(), orientation: turned)

        // A horizontal ruler on a picture turned a quarter is a vertical one
        // on the film: the middle column carries it, the middle row does not.
        XCTAssertNotEqual(pixel(burned, x: 256, y: 200), 128)
        XCTAssertNotEqual(pixel(burned, x: 256, y: 300), 128)
        XCTAssertEqual(pixel(burned, x: 150, y: 256), 128)
        XCTAssertEqual(pixel(burned, x: 350, y: 256), 128)
    }
    #endif

    // MARK: - The model on disk

    func test_sidecarWithoutTheNewKeysStillReads() throws {
        let legacy = """
        {"id":"6B29FC40-CA47-1067-B31D-00DD010662DA","kind":"text",
         "start":{"x":0.25,"y":0.5},"end":{"x":0.25,"y":0.5},
         "text":"Nodule","scale":0.04,"color":{"red":1,"green":0.85,"blue":0.1}}
        """
        let decoded = try JSONDecoder().decode(
            PrintOverlayAnnotation.self, from: Data(legacy.utf8))
        XCTAssertEqual(decoded.kind, .text)
        XCTAssertTrue(decoded.points.isEmpty)
        XCTAssertFalse(decoded.filled)
        XCTAssertFalse(decoded.isLocked)
    }

    func test_aPlainAnnotationEncodesNoNewKeys() throws {
        let annotation = PrintOverlayAnnotation(
            kind: .text, start: PrintOverlayPoint(x: 0.25, y: 0.5), text: "Nodule")
        let json = String(decoding: try JSONEncoder().encode(annotation), as: UTF8.self)
        XCTAssertFalse(json.contains("points"))
        XCTAssertFalse(json.contains("isLocked"))
        XCTAssertFalse(json.contains("filled"))
    }

    func test_aShapeRoundTripsThroughJSON() throws {
        let circle = PrintOverlayAnnotation(
            shape: .circle,
            points: [PrintOverlayPoint(x: 0.5, y: 0.5), PrintOverlayPoint(x: 0.7, y: 0.5)],
            filled: true, color: .green)
        let data = try JSONEncoder().encode(circle)
        let back = try JSONDecoder().decode(PrintOverlayAnnotation.self, from: data)
        XCTAssertEqual(back, circle)
    }

    func test_aShapeSavedByThisAppLeavesAsTheGraphicObjectItCameFrom() throws {
        let circle = PrintOverlayAnnotation(
            shape: .circle,
            points: [PrintOverlayPoint(x: 0.5, y: 0.5), PrintOverlayPoint(x: 0.75, y: 0.5)],
            color: .green)
        let display = ViewerPresentationStateBridge.capture(
            presentation: ViewerPresentation(zoom: 1, viewportWidth: 512, viewportHeight: 512),
            windowCenter: 40, windowWidth: 400, imageWidth: 512, imageHeight: 512)

        let saved = try store.save(
            images: [.init(
                sopClassUID: ctSOPClass, sopInstanceUID: imageA, seriesInstanceUID: seriesUID,
                display: display, annotations: [circle], imageWidth: 512, imageHeight: 512)],
            label: "With ROI",
            patient: PresentationStatePatientContext(studyInstanceUID: studyUID))

        let url = try XCTUnwrap(saved?.states.first?.url)
        let parsed = try GrayscalePresentationStateParser().parse(
            dataSet: try DICOMFile.read(from: url).dataSet)
        let object = try XCTUnwrap(parsed.graphicAnnotations.first?.graphicObjects.first)
        XCTAssertEqual(object.type, .circle)
        XCTAssertEqual(object.data, [256, 256, 384, 256])
    }
}
