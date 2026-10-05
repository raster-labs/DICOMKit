// ViewerDisplayPipelineTests.swift
// DICOMStudioTests
//
// The viewer renders through the PS3.4 N.2 chain: the image's Modality LUT,
// then the window applied to its output (PS3.3 2026a C.11.2.1.2.1), then the
// Presentation LUT. The viewer keeps its window in stored-pixel units for the
// tools and the panel, and these tests pin that the picture it shows is the
// standard's regardless (D65, D68), that a MONOCHROME1 image saves and restores
// with the right Presentation LUT and a colour image as a Color Softcopy
// Presentation State (D42), and that a presentation state without a Modality
// LUT is the identity (PS3.4 N.2.1.1, D28 / S-2).

import Testing
@testable import DICOMStudio
import DICOMCore
import DICOMKit
import DICOMPrintKit
import Foundation

#if canImport(CoreGraphics)
import CoreGraphics

@MainActor
@Suite("Viewer display pipeline (PS3.4 N.2)")
struct ViewerDisplayPipelineTests {

    private static let studyUID = "1.2.3.4.5"
    private static let seriesUID = "1.2.3.4.5.6"
    private static let sopUID = "1.2.3.4.5.6.7"
    private static let ctSOPClass = "1.2.840.10008.5.1.4.1.1.2"

    // MARK: - Fixtures

    /// A one-row signed 16-bit monochrome file with the given rescale and header window.
    private static func writeMonochromeFile(
        stored: [Int16], slope: String, intercept: String,
        windowCenter: String, windowWidth: String,
        photometric: String = "MONOCHROME2"
    ) throws -> (path: String, root: URL) {
        var elements: [DataElement] = [
            .uint16(tag: .rows, value: 1),
            .uint16(tag: .columns, value: UInt16(stored.count)),
            .uint16(tag: .bitsAllocated, value: 16),
            .uint16(tag: .bitsStored, value: 16),
            .uint16(tag: .highBit, value: 15),
            .uint16(tag: .pixelRepresentation, value: 1),
            .uint16(tag: .samplesPerPixel, value: 1),
            .string(tag: .photometricInterpretation, vr: .CS, value: photometric),
            .string(tag: .rescaleIntercept, vr: .DS, value: intercept),
            .string(tag: .rescaleSlope, vr: .DS, value: slope),
            .string(tag: .windowCenter, vr: .DS, value: windowCenter),
            .string(tag: .windowWidth, vr: .DS, value: windowWidth),
            .string(tag: .sopClassUID, vr: .UI, value: ctSOPClass),
            .string(tag: .sopInstanceUID, vr: .UI, value: sopUID),
            .string(tag: .studyInstanceUID, vr: .UI, value: studyUID),
            .string(tag: .seriesInstanceUID, vr: .UI, value: seriesUID)
        ]
        var pixels = Data()
        for value in stored {
            let bits = UInt16(bitPattern: value)
            pixels.append(UInt8(bits & 0xFF))
            pixels.append(UInt8(bits >> 8))
        }
        elements.append(DataElement(
            tag: .pixelData, vr: .OW, length: UInt32(pixels.count), valueData: pixels))
        let data = try DICOMFile.create(
            dataSet: DataSet(elements: elements),
            transferSyntaxUID: TransferSyntax.explicitVRLittleEndian.uid).write()
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ViewerDisplayPipelineTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let url = root.appendingPathComponent("frame.dcm")
        try data.write(to: url)
        return (url.path, root)
    }

    /// A viewer over a header-only image, with saved views kept in a temporary place.
    private static func makeViewModel(
        photometric: String, samplesPerPixel: Int = 1,
        rescaleSlope: Double = 1, rescaleIntercept: Double = 0, rescaleType: String? = nil
    ) -> (ImageViewerViewModel, URL) {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ViewerDisplayPipelineTests-\(UUID().uuidString)")
        var elements: [DataElement] = [
            .string(tag: .sopClassUID, vr: .UI, value: ctSOPClass),
            .string(tag: .sopInstanceUID, vr: .UI, value: sopUID),
            .string(tag: .studyInstanceUID, vr: .UI, value: studyUID),
            .string(tag: .seriesInstanceUID, vr: .UI, value: seriesUID),
            .string(tag: .patientName, vr: .PN, value: "DOE^JANE"),
            .string(tag: .patientID, vr: .LO, value: "12345"),
            .string(tag: .photometricInterpretation, vr: .CS, value: photometric),
            .uint16(tag: .samplesPerPixel, value: UInt16(samplesPerPixel)),
            .string(tag: .rescaleSlope, vr: .DS, value: "\(rescaleSlope)"),
            .string(tag: .rescaleIntercept, vr: .DS, value: "\(rescaleIntercept)"),
            .string(tag: .windowCenter, vr: .DS, value: "40"),
            .string(tag: .windowWidth, vr: .DS, value: "400")
        ]
        if let rescaleType {
            elements.append(.string(tag: .rescaleType, vr: .LO, value: rescaleType))
        }
        let file = DICOMFile.create(
            dataSet: DataSet(elements: elements),
            sopClassUID: ctSOPClass, sopInstanceUID: sopUID)

        let viewModel = ImageViewerViewModel()
        viewModel.dicomFile = file
        viewModel.filePath = "/tmp/frame.dcm"
        viewModel.sopInstanceUID = sopUID
        viewModel.studyInstanceUID = studyUID
        viewModel.currentSeriesUID = seriesUID
        viewModel.imageColumns = 512
        viewModel.imageRows = 512
        viewModel.viewContentWidth = 800
        viewModel.viewContentHeight = 600
        viewModel.photometricInterpretation = photometric
        viewModel.samplesPerPixel = samplesPerPixel
        viewModel.rescaleSlope = rescaleSlope
        viewModel.rescaleIntercept = rescaleIntercept
        viewModel.presentationStateStore = PresentationStateStore(root: root)
        return (viewModel, root)
    }

    /// The rendered greys, read back through an 8-bit grey context so the
    /// backend's own pixel format does not matter.
    private static func greys(_ image: CGImage) -> [UInt8] {
        let width = image.width, height = image.height
        var grey = [UInt8](repeating: 0, count: width * height)
        guard let context = CGContext(
            data: &grey, width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: width, space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return [] }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return grey
    }

    /// PS3.3 C.11.2.1.2.1 LINEAR, as the pseudo-code states it, over a modality value
    /// (floored to the byte, as `WindowLUT.displayByte` quantises).
    private static func linearByte(_ x: Double, _ c: Double, _ w: Double) -> UInt8 {
        if x <= c - 0.5 - (w - 1) / 2 { return 0 }
        if x > c - 0.5 + (w - 1) / 2 { return 255 }
        return UInt8(((x - (c - 0.5)) / (w - 1) + 0.5) * 255 + 1e-9)
    }

    // MARK: - D65 / D68: the window applies after the Modality LUT

    @Test("Slope 2: the header window is applied to the rescaled value (C.11.2.1.2.1)")
    func slopeTwoWindowsTheModalityValue() throws {
        let stored: [Int16] = [-100, -26, -25, -24, 0, 24, 25, 26, 100]
        let (path, root) = try Self.writeMonochromeFile(
            stored: stored, slope: "2", intercept: "0", windowCenter: "0", windowWidth: "100")
        defer { try? FileManager.default.removeItem(at: root) }

        let vm = ImageViewerViewModel()
        vm.loadFile(at: path)
        // The viewer's convention: stored units on the tools (w / |m|)…
        #expect(vm.windowCenter == 0)
        #expect(vm.windowWidth == 50)
        // …and modality units on the way to the renderer, after the Modality LUT.
        #expect(vm.displayModalityLUT == .rescale(slope: 2, intercept: 0, type: nil))
        #expect(vm.displayWindow.center == 0)
        #expect(vm.displayWindow.width == 100)

        vm.renderCurrentFrame()
        let image = try #require(vm.currentImage)
        #expect(Self.greys(image) == stored.map { Self.linearByte(2 * Double($0), 0, 100) })
    }

    @Test("Slope −1: the ramp follows the modality value, not the stored order")
    func negativeSlopeIsNotInverted() throws {
        let stored: [Int16] = [-100, 0, 49, 50, 51, 100, 200]
        let (path, root) = try Self.writeMonochromeFile(
            stored: stored, slope: "-1", intercept: "100", windowCenter: "100", windowWidth: "100")
        defer { try? FileManager.default.removeItem(at: root) }

        let vm = ImageViewerViewModel()
        vm.loadFile(at: path)
        vm.renderCurrentFrame()
        let greys = Self.greys(try #require(vm.currentImage))
        let expected = stored.map { Self.linearByte(100 - Double($0), 100, 100) }
        #expect(expected.first == 255)
        #expect(expected.last == 0)
        #expect(greys == expected)
    }

    @Test("A dragged window keeps its modality meaning through a slope of 2")
    func adjustedWindowRendersInModalityUnits() throws {
        let stored: [Int16] = [-100, -26, -25, -24, 0, 24, 25, 26, 100]
        let (path, root) = try Self.writeMonochromeFile(
            stored: stored, slope: "2", intercept: "0", windowCenter: "0", windowWidth: "100")
        defer { try? FileManager.default.removeItem(at: root) }

        let vm = ImageViewerViewModel()
        vm.loadFile(at: path)
        // A preset of 50 / 100 modality units lands as 25 / 50 stored…
        vm.applyPreset(WindowLevelPreset(name: "Test", center: 50, width: 100, modality: "CT"))
        #expect(vm.windowCenter == 25)
        #expect(vm.windowWidth == 50)
        // …and renders as the 50 / 100 window over 2·s.
        let greys = Self.greys(try #require(vm.currentImage))
        #expect(greys == stored.map { Self.linearByte(2 * Double($0), 50, 100) })
    }

    @Test("Tiles: a stored-unit window renders the same chain as its modality-unit twin")
    func tileRendersThroughTheChain() async throws {
        let stored: [Int16] = [-100, -26, -25, -24, 0, 24, 25, 26, 100]
        let (path, root) = try Self.writeMonochromeFile(
            stored: stored, slope: "2", intercept: "0", windowCenter: "0", windowWidth: "100")
        defer { try? FileManager.default.removeItem(at: root) }

        let expected = stored.map { Self.linearByte(2 * Double($0), 0, 100) }
        let viewer = await FrameRenderer.render(
            path: path, frameIndex: 0, windowCenter: 0, windowWidth: 50,
            windowSpace: .storedValues, presentation: nil, maxDimension: 64)
        let typed = await FrameRenderer.render(
            path: path, frameIndex: 0, windowCenter: 0, windowWidth: 100,
            windowSpace: .outputUnits, presentation: nil, maxDimension: 64)
        let unwindowed = await FrameRenderer.render(
            path: path, frameIndex: 0, windowCenter: nil, windowWidth: nil,
            presentation: nil, maxDimension: 64)
        #expect(Self.greys(try #require(viewer)) == expected)
        #expect(Self.greys(try #require(typed)) == expected)
        #expect(Self.greys(try #require(unwindowed)) == expected,
                "no window resolves to the file's own, after the Modality LUT")
    }

    @Test("ImageRenderingService renders a header-unit window after the Modality LUT")
    func renderingServiceWindowsTheModalityValue() throws {
        let stored: [Int16] = [-100, -26, -25, -24, 0, 24, 25, 26, 100]
        let (path, root) = try Self.writeMonochromeFile(
            stored: stored, slope: "2", intercept: "0", windowCenter: "0", windowWidth: "100")
        defer { try? FileManager.default.removeItem(at: root) }

        let service = ImageRenderingService()
        // The file's own window (0 / 100 in modality units) over 2·s …
        let own = try #require(try service.renderFrame(filePath: path))
        #expect(Self.greys(own) == stored.map { Self.linearByte(2 * Double($0), 0, 100) })
        // … and an explicit one, stated in the same units.
        let file = try DICOMFile.read(from: URL(fileURLWithPath: path))
        let explicit = try #require(service.renderFrame(from: file, windowCenter: 50, windowWidth: 100))
        #expect(Self.greys(explicit) == stored.map { Self.linearByte(2 * Double($0), 50, 100) })
    }

    // MARK: - D42: photometric and Rescale Type reach the saved view

    @Test("A MONOCHROME1 image shown upright saves as INVERSE and restores upright (PS3.4 N.2)")
    func monochrome1SavesAndRestoresItsPolarity() throws {
        let (vm, root) = Self.makeViewModel(photometric: "MONOCHROME1")
        defer { try? FileManager.default.removeItem(at: root) }

        vm.zoomLevel = 2.5
        #expect(vm.saveCurrentView(label: "Upright"))
        let view = try #require(vm.savedViewsForCurrentImage.first { $0.label == "Upright" })
        let state = try #require(view.state(forImage: Self.sopUID)).state
        #expect(state.presentationLUT == .inverse)

        vm.isInverted = true
        #expect(vm.applySavedView(view))
        #expect(vm.isInverted == false)

        // And the inverted reading of the same image is IDENTITY.
        vm.isInverted = true
        vm.zoomLevel = 3
        #expect(vm.saveCurrentView(label: "Inverted"))
        let inverted = try #require(vm.savedViewsForCurrentImage.first { $0.label == "Inverted" })
        #expect(try #require(inverted.state(forImage: Self.sopUID)).state.presentationLUT == .identity)
        vm.isInverted = false
        #expect(vm.applySavedView(inverted))
        #expect(vm.isInverted == true)
    }

    @Test("A colour image is saved as a Color Softcopy Presentation State (PS3.3 A.33.1.1)")
    func colourImageSavesAsColorSoftcopy() throws {
        let (vm, root) = Self.makeViewModel(photometric: "RGB", samplesPerPixel: 3)
        defer { try? FileManager.default.removeItem(at: root) }

        vm.zoomLevel = 2.5
        #expect(vm.saveCurrentView(label: "Zoomed"))
        let view = try #require(vm.savedViewsForCurrentImage.first)
        let stored = try #require(view.state(forImage: Self.sopUID))
        #expect(stored.state.sopClassUID == "1.2.840.10008.5.1.4.1.1.11.2")
        #expect(stored.state.modalityLUT == nil)
    }

    @Test("The image's Rescale Type is written with the state's Modality LUT (PS3.4 N.2.1.1)")
    func rescaleTypeReachesTheState() throws {
        let (vm, root) = Self.makeViewModel(
            photometric: "MONOCHROME2", rescaleSlope: 1, rescaleIntercept: -1024, rescaleType: "HU")
        defer { try? FileManager.default.removeItem(at: root) }

        vm.zoomLevel = 2.5
        #expect(vm.saveCurrentView(label: "Lung"))
        let view = try #require(vm.savedViewsForCurrentImage.first)
        let state = try #require(view.state(forImage: Self.sopUID)).state
        #expect(state.modalityLUT == .rescale(slope: 1, intercept: -1024, type: "HU"))
    }

    // MARK: - D28 / S-2: a state without a Modality LUT is the identity

    private static func savedView(
        modalityLUT: ModalityLUT?, center: Double, width: Double, isImported: Bool, root: URL
    ) -> SavedView {
        let state = GrayscalePresentationState(
            sopInstanceUID: "1.2.3.9",
            referencedSeries: [ReferencedSeries(
                seriesInstanceUID: seriesUID,
                referencedImages: [ReferencedImage(sopClassUID: ctSOPClass, sopInstanceUID: sopUID)])],
            modalityLUT: modalityLUT,
            voiLUT: .window(center: center, width: width, explanation: nil, function: .linear))
        return SavedView(label: "Other", created: nil, states: [
            StoredPresentationState(state: state, url: root.appendingPathComponent("pr.dcm"),
                                    isImported: isImported)
        ])
    }

    @Test("An adopted PR with no Modality LUT windows stored values (PS3.4 N.2.1.1)")
    func importedStateWithoutModalityLUTIsIdentity() throws {
        let (vm, root) = Self.makeViewModel(
            photometric: "MONOCHROME2", rescaleSlope: 1, rescaleIntercept: -1024)
        defer { try? FileManager.default.removeItem(at: root) }

        let view = Self.savedView(modalityLUT: nil, center: 40, width: 400, isImported: true, root: root)
        #expect(vm.applySavedView(view))
        // Not the image's rescale: 40 stays 40, and the frame renders with no Modality LUT.
        #expect(vm.windowCenter == 40)
        #expect(vm.windowWidth == 400)
        #expect(vm.displayModalityLUT == nil)
        #expect(vm.displayWindow.center == 40)

        // Moving a tool leaves the state, and the image's own Modality LUT comes back.
        vm.adjustWindowLevel(deltaX: 0, deltaY: 1)
        #expect(vm.modalityLUTSource == .image)
        #expect(vm.displayModalityLUT == .rescale(slope: 1, intercept: -1024, type: nil))
    }

    @Test("This app's own pre-2026-09-29 objects (no Modality LUT) keep the image's rescale")
    func ownLegacyStateMigratesToTheImageRescale() throws {
        let (vm, root) = Self.makeViewModel(
            photometric: "MONOCHROME2", rescaleSlope: 1, rescaleIntercept: -1024)
        defer { try? FileManager.default.removeItem(at: root) }

        let view = Self.savedView(modalityLUT: nil, center: 40, width: 400, isImported: false, root: root)
        #expect(vm.applySavedView(view))
        #expect(vm.windowCenter == 1064)
        #expect(vm.windowWidth == 400)
        #expect(vm.displayModalityLUT == .rescale(slope: 1, intercept: -1024, type: nil))
        #expect(vm.displayWindow.center == 40)
    }

    @Test("A PR's own Modality LUT replaces the image's while the view is shown")
    func stateModalityLUTReplacesTheImages() throws {
        let (vm, root) = Self.makeViewModel(
            photometric: "MONOCHROME2", rescaleSlope: 1, rescaleIntercept: -1024)
        defer { try? FileManager.default.removeItem(at: root) }

        let view = Self.savedView(
            modalityLUT: .rescale(slope: 2, intercept: 0, type: nil),
            center: 100, width: 100, isImported: true, root: root)
        #expect(vm.applySavedView(view))
        #expect(vm.windowCenter == 50)
        #expect(vm.windowWidth == 50)
        #expect(vm.displayModalityLUT == .rescale(slope: 2, intercept: 0, type: nil))
        #expect(vm.displayWindow.center == 100)
        #expect(vm.displayWindow.width == 100)

        vm.applyDefaultView()
        #expect(vm.modalityLUTSource == .image)
    }

    // MARK: - D28: OV is a binary VR

    @Test("The inspector shows every PS3.5 Table 6.2-1 'Other' VR and UN as bytes")
    func inspectorTreatsOVAsBinary() {
        let bytes = Data([0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08, 0x09])
        for vr in [VR.OB, .OD, .OF, .OL, .OV, .OW, .UN] {
            let element = DataElement(
                tag: .extendedOffsetTable, vr: vr, length: UInt32(bytes.count), valueData: bytes)
            let shown = DICOMInspectorHelpers.displayValue(for: element)
            #expect(shown == "01 02 03 04 05 06 07 08 … [9 bytes]", "\(vr)")
        }
    }
}
#endif
