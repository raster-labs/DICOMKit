//
// PresentationStateIODConformanceTests.swift
// DICOMPrintKit
//
// What the store writes, held against the IOD tables of PS3.3 2026a (D27, D36):
// the Type 1 Displayed Area Selection Sequence for a fitted view (Table C.10-4),
// the state's own Modality LUT (PS3.4 N.2.1.1), the Color Softcopy
// Presentation State for a colour image (A.33.1.1, Table A.33.2-1), the
// MONOCHROME1 polarity folded into the Presentation LUT (PS3.4 N.2), and shutter
// pixel positions read as 1-based pixels (Table C.7-17a).
//

import XCTest
import DICOMCore
import DICOMKit
@testable import DICOMPrintKit

final class PresentationStateIODConformanceTests: XCTestCase {

    private var root: URL!
    private var store: PresentationStateStore!

    private let studyUID = "1.2.3.4.5"
    private let seriesUID = "1.2.3.4.5.6"

    override func setUpWithError() throws {
        try super.setUpWithError()
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("PresentationStateIODConformanceTests-\(UUID().uuidString)")
        store = PresentationStateStore(root: root)
    }

    override func tearDownWithError() throws {
        if let root, FileManager.default.fileExists(atPath: root.path) {
            try FileManager.default.removeItem(at: root)
        }
        try super.tearDownWithError()
    }

    // MARK: - Fixtures

    private func context() -> PresentationStatePatientContext {
        PresentationStatePatientContext(
            patientName: "DOE^JANE", patientID: "12345",
            studyInstanceUID: studyUID, studyDate: "20260101")
    }

    private func image(
        invert: Bool = false,
        palette: PseudoColorPalette? = nil,
        width: Int = 512,
        height: Int = 512,
        slope: Double = 1,
        intercept: Double = 0,
        rescaleType: String? = nil,
        photometric: String? = nil
    ) -> PresentationStateStore.ImageToSave {
        // A fitted view: the whole image visible, so the bridge records no
        // Displayed Area of its own.
        let display = ViewerPresentationStateBridge.capture(
            presentation: ViewerPresentation(
                viewportWidth: 800, viewportHeight: 600, invert: invert),
            windowCenter: 40, windowWidth: 400,
            imageWidth: width, imageHeight: height,
            photometricInterpretation: photometric)
        return PresentationStateStore.ImageToSave(
            sopClassUID: "1.2.840.10008.5.1.4.1.1.2",
            sopInstanceUID: "1.2.3.4.5.6.7",
            seriesInstanceUID: seriesUID,
            display: display,
            palette: palette,
            imageWidth: width, imageHeight: height,
            bitsStored: 12,
            rescaleSlope: slope, rescaleIntercept: intercept,
            photometricInterpretation: photometric,
            rescaleType: rescaleType)
    }

    private func savedDataSet(_ image: PresentationStateStore.ImageToSave) throws -> DataSet {
        let view = try XCTUnwrap(store.save(images: [image], label: "View", patient: context()))
        let url = try XCTUnwrap(view.states.first?.url)
        return try DICOMFile.read(from: url).dataSet
    }

    // MARK: - D27 / D36: Displayed Area (PS3.3 Table C.10-4)

    /// A fitted view has no area of its own; the Type 1 sequence is still
    /// written, as the whole image — what the absence meant to the viewer.
    func test_fittedView_writesTheWholeImageAsTheDisplayedArea() throws {
        let dataSet = try savedDataSet(image(width: 640, height: 480))
        let area = try XCTUnwrap(dataSet[.displayedAreaSelectionSequence]?.sequenceItems?.first,
                                 "Displayed Area Selection Sequence (0070,005A) is Type 1")
        XCTAssertEqual(area[.displayedAreaTopLeftHandCorner]?.int32Values, [1, 1])
        XCTAssertEqual(area[.displayedAreaBottomRightHandCorner]?.int32Values, [640, 480])
        XCTAssertEqual(area.string(for: .presentationSizeMode), "SCALE TO FIT")
    }

    func test_pseudoColorView_writesTheDisplayedAreaToo() throws {
        let dataSet = try savedDataSet(image(palette: .hotIron))
        XCTAssertEqual(dataSet.string(for: .sopClassUID), PseudoColorPresentationStateBuilder.sopClassUID)
        XCTAssertNotNil(dataSet[.displayedAreaSelectionSequence]?.sequenceItems?.first)
    }

    // MARK: - D27: the state's own Modality LUT (PS3.4 N.2.1.1)

    /// The window is in HU; without the rescale in the state a conforming
    /// viewer would apply it to stored values.
    func test_rescaledImage_carriesItsRescaleInTheState() throws {
        let dataSet = try savedDataSet(image(slope: 1, intercept: -1024, rescaleType: "HU"))
        XCTAssertEqual(dataSet.string(for: .rescaleIntercept)?.trimmingCharacters(in: .whitespaces), "-1024")
        XCTAssertEqual(dataSet.string(for: .rescaleSlope)?.trimmingCharacters(in: .whitespaces), "1")
        XCTAssertEqual(dataSet.string(for: .rescaleType)?.trimmingCharacters(in: .whitespaces), "HU")
    }

    func test_rescaleTypeUnknown_isWrittenAsUnspecified() throws {
        let dataSet = try savedDataSet(image(slope: 2, intercept: 0))
        XCTAssertEqual(dataSet.string(for: .rescaleType)?.trimmingCharacters(in: .whitespaces), "US")
    }

    /// An identity rescale has nothing to apply; absence already means identity.
    func test_identityRescale_writesNoModalityLUT() throws {
        let dataSet = try savedDataSet(image())
        XCTAssertNil(dataSet[.rescaleIntercept])
        XCTAssertNil(dataSet[.modalityLUTSequence])
    }

    func test_storedState_readsBackTheModalityLUT() throws {
        try store.save(images: [image(slope: 1, intercept: -1024, rescaleType: "HU")],
                       label: "CT", patient: context())
        let state = try XCTUnwrap(store.views(forStudy: studyUID).first?.states.first?.state)
        guard case .rescale(let slope, let intercept, _)? = state.modalityLUT else {
            return XCTFail("the parsed state carries no rescale")
        }
        XCTAssertEqual(slope, 1)
        XCTAssertEqual(intercept, -1024)
    }

    // MARK: - D27: colour images (A.33.1.1, Table A.33.2-1)

    func test_colourImage_isSavedAsAColorSoftcopyPresentationState() throws {
        let dataSet = try savedDataSet(image(photometric: "RGB"))
        XCTAssertEqual(dataSet.string(for: .sopClassUID), "1.2.840.10008.5.1.4.1.1.11.2")
        XCTAssertNotNil(dataSet[.iccProfile], "ICC Profile module is M in Table A.33.2-1")
        XCTAssertNil(dataSet[.presentationLUTShape], "no Softcopy Presentation LUT module")
        XCTAssertNil(dataSet[.windowCenter], "no Softcopy VOI LUT module")
        XCTAssertNil(dataSet[.rescaleIntercept], "no Modality LUT module")
        XCTAssertNotNil(dataSet[.displayedAreaSelectionSequence]?.sequenceItems?.first)
    }

    func test_colourImageWithAPalette_isStillAColorState() throws {
        // Pseudo-Color may only reference monochrome images (A.33.3).
        let dataSet = try savedDataSet(image(palette: .hotIron, photometric: "YBR_FULL_422"))
        XCTAssertEqual(dataSet.string(for: .sopClassUID), ColorPresentationStateBuilder.sopClassUID)
    }

    func test_invertedColourImage_restoresInverted() throws {
        try store.save(images: [image(invert: true, photometric: "RGB")], label: "Inv", patient: context())
        let state = try XCTUnwrap(store.views(forStudy: studyUID).first?.states.first?.state)
        XCTAssertEqual(state.sopClassUID, ColorPresentationStateBuilder.sopClassUID)
        XCTAssertEqual(state.presentationLUT, .inverse)
    }

    func test_monochromeImage_staysGrayscale() throws {
        let dataSet = try savedDataSet(image(photometric: "MONOCHROME2"))
        XCTAssertEqual(dataSet.string(for: .sopClassUID), GrayscalePresentationStateBuilder.sopClassUID)
    }

    // MARK: - MONOCHROME1 (PS3.4 N.2)

    /// The image's photometric is ignored under a presentation state, so the
    /// picture the reader saw — lowest value white — is INVERSE.
    func test_monochrome1_uprightViewIsInverse() {
        let upright = ViewerPresentationStateBridge.capture(
            presentation: ViewerPresentation(), windowCenter: nil, windowWidth: nil,
            imageWidth: 100, imageHeight: 100, photometricInterpretation: "MONOCHROME1")
        XCTAssertEqual(upright.presentationLUT, .inverse)

        let inverted = ViewerPresentationStateBridge.capture(
            presentation: ViewerPresentation(invert: true), windowCenter: nil, windowWidth: nil,
            imageWidth: 100, imageHeight: 100, photometricInterpretation: "MONOCHROME1")
        XCTAssertEqual(inverted.presentationLUT, .identity)
    }

    func test_monochrome1_restoresTheViewItWasSavedFrom() {
        for invert in [false, true] {
            let captured = ViewerPresentationStateBridge.capture(
                presentation: ViewerPresentation(invert: invert), windowCenter: nil, windowWidth: nil,
                imageWidth: 100, imageHeight: 100, photometricInterpretation: "MONOCHROME1")
            let state = GrayscalePresentationState(
                sopInstanceUID: "1.2.3", referencedSeries: [],
                presentationLUT: captured.presentationLUT)
            let restored = ViewerPresentationStateBridge.restore(
                state, imageWidth: 100, imageHeight: 100,
                viewportWidth: 100, viewportHeight: 100,
                photometricInterpretation: "MONOCHROME1")
            XCTAssertEqual(restored.invert, invert)
        }
    }

    func test_noPhotometric_keepsTheMonochrome2Reading() {
        let captured = ViewerPresentationStateBridge.capture(
            presentation: ViewerPresentation(invert: true), windowCenter: nil, windowWidth: nil,
            imageWidth: 100, imageHeight: 100)
        XCTAssertEqual(captured.presentationLUT, .inverse)
    }

    // MARK: - Shutter pixel positions (PS3.3 Table C.7-17a)

    /// Edges 1 and 512 on a 512-pixel image leave the whole image open: the
    /// edge pixels are inside, and pixel 1 starts at the image's left edge.
    func test_rectangularShutter_edgePixelsAreOpen() throws {
        let overlay = try XCTUnwrap(PresentationStateStore.shutterOverlay(
            .rectangular(left: 1, right: 512, top: 1, bottom: 512, presentationValue: nil),
            imageWidth: 512, imageHeight: 512))
        XCTAssertEqual(overlay.points.map(\.x), [0, 1])
        XCTAssertEqual(overlay.points.map(\.y), [0, 1])
    }

    func test_rectangularShutter_opensFromTheLeftEdgeOfItsFirstPixel() throws {
        let overlay = try XCTUnwrap(PresentationStateStore.shutterOverlay(
            .rectangular(left: 101, right: 200, top: 51, bottom: 150, presentationValue: nil),
            imageWidth: 400, imageHeight: 400))
        XCTAssertEqual(overlay.points[0].x, 100.0 / 400, accuracy: 1e-12)
        XCTAssertEqual(overlay.points[0].y, 50.0 / 400, accuracy: 1e-12)
        XCTAssertEqual(overlay.points[1].x, 200.0 / 400, accuracy: 1e-12)
        XCTAssertEqual(overlay.points[1].y, 150.0 / 400, accuracy: 1e-12)
    }

    func test_circularShutter_isCentredOnItsPixel() throws {
        let overlay = try XCTUnwrap(PresentationStateStore.shutterOverlay(
            .circular(centerColumn: 256, centerRow: 128, radius: 100, presentationValue: nil),
            imageWidth: 512, imageHeight: 512))
        XCTAssertEqual(overlay.points[0].x, 255.5 / 512, accuracy: 1e-12)
        XCTAssertEqual(overlay.points[0].y, 127.5 / 512, accuracy: 1e-12)
        XCTAssertEqual(overlay.points[1].x - overlay.points[0].x, 100.0 / 512, accuracy: 1e-12)
    }
}
