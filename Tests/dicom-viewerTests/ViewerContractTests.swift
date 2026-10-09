//
// ViewerContractTests.swift
// dicom-viewer
//
// Grayscale display pinned to DICOM 2026a: PS3.3 C.11.1.1.2 (Rescale), Table C.11-2b and
// C.11.2.1.2.1 / C.11.2.1.3 (VOI LUT Function LINEAR, LINEAR_EXACT, SIGMOID; LINEAR when
// absent; width rules), C.7.6.3.1.2 (MONOCHROME1 minimum shown white), Table C.9-2 (Overlay
// Origin 1\1 = upper left pixel), frame numbers starting at 1, PS3.6 Table 6-1 labels.
//

import XCTest
import ArgumentParser
import DICOMCore
import DICOMKit
@testable import dicom_viewer

final class ViewerContractTests: XCTestCase {

    /// 1-row image of 16-bit stored values.
    private static func file(values: [UInt16], rows: Int = 1, photometric: String = "MONOCHROME2",
                             window: (Double, Double)? = nil, function: String? = nil,
                             intercept: Double = 0, frames: Int = 1,
                             configure: (inout DataSet) -> Void = { _ in }) -> DICOMFile {
        var ds = DataSet()
        let columns = values.count / rows / frames
        ds.setString("1.2.840.10008.5.1.4.1.1.2", for: .sopClassUID, vr: .UI)
        ds.setString("1.2.3.4", for: .sopInstanceUID, vr: .UI)
        ds.setUInt16(UInt16(rows), for: .rows)
        ds.setUInt16(UInt16(columns), for: .columns)
        ds.setUInt16(16, for: .bitsAllocated)
        ds.setUInt16(12, for: .bitsStored)
        ds.setUInt16(11, for: .highBit)
        ds.setUInt16(0, for: .pixelRepresentation)
        ds.setUInt16(1, for: .samplesPerPixel)
        ds.setString(photometric, for: .photometricInterpretation, vr: .CS)
        if frames > 1 { ds.setString(String(frames), for: .numberOfFrames, vr: .IS) }
        ds.setString("1", for: .rescaleSlope, vr: .DS)
        ds.setString(String(intercept), for: .rescaleIntercept, vr: .DS)
        if let window {
            ds.setString(String(window.0), for: .windowCenter, vr: .DS)
            ds.setString(String(window.1), for: .windowWidth, vr: .DS)
        }
        if let function { ds.setString(function, for: .voiLUTFunction, vr: .CS) }
        var data = Data()
        for v in values { data.append(UInt8(v & 0xFF)); data.append(UInt8(v >> 8)) }
        ds[.pixelData] = DataElement.data(tag: .pixelData, vr: .OW, data: data)
        configure(&ds)
        return DICOMFile.create(dataSet: ds, sopClassUID: "1.2.840.10008.5.1.4.1.1.2", sopInstanceUID: "1.2.3.4")
    }

    // MARK: - VOI LUT Function (Table C.11-2b, C.11.2.1.2.1, C.11.2.1.3)

    func testWindowWithoutFunctionIsLinear() throws {
        let image = try TerminalRenderer(dicomFile: Self.file(values: [40, 100], window: (40, 400))).extractPixels()
        // LINEAR: ((x - (c - 0.5)) / (w - 1)) + 0.5
        XCTAssertEqual(image.pixels[0], (40 - 39.5) / 399 + 0.5, accuracy: 1e-12)
        XCTAssertEqual(image.pixels[1], (100 - 39.5) / 399 + 0.5, accuracy: 1e-12)
    }

    func testVOILUTFunctionFromFileIsHonoured() throws {
        let sigmoid = try TerminalRenderer(dicomFile: Self.file(values: [140], window: (40, 400), function: "SIGMOID"))
            .extractPixels()
        XCTAssertEqual(sigmoid.pixels[0], 1 / (1 + exp(-4.0 * 100 / 400)), accuracy: 1e-12)
        let exact = try TerminalRenderer(dicomFile: Self.file(values: [40], window: (40, 400), function: "LINEAR_EXACT"))
            .extractPixels()
        XCTAssertEqual(exact.pixels[0], 0.5, accuracy: 1e-12)
        // A command-line function overrides the file's.
        let overridden = try TerminalRenderer(dicomFile: Self.file(values: [40], window: (40, 400), function: "SIGMOID"))
            .extractPixels(voiFunction: .linearExact)
        XCTAssertEqual(overridden.pixels[0], 0.5, accuracy: 1e-12)
    }

    func testAutoWindowUsesRescaledRange() throws {
        let image = try TerminalRenderer(dicomFile: Self.file(values: [0, 50, 100], intercept: -1024)).extractPixels()
        XCTAssertEqual(image.pixels[0], 0, accuracy: 1e-12)
        XCTAssertEqual(image.pixels[1], 0.5, accuracy: 1e-12)
        XCTAssertEqual(image.pixels[2], 1, accuracy: 1e-12)
    }

    // MARK: - MONOCHROME1 (C.7.6.3.1.2)

    func testMonochrome1MinimumIsWhite() throws {
        let renderer = TerminalRenderer(dicomFile: Self.file(values: [0, 100], photometric: "MONOCHROME1"))
        let image = try renderer.extractPixels()
        XCTAssertEqual(image.pixels, [1, 0])
        XCTAssertEqual(try renderer.extractPixels(invert: true).pixels, [0, 1])
    }

    // MARK: - Overlay planes (Table C.9-2)

    func testOverlayOriginIsOneBasedRowColumn() throws {
        // 3x4 image; a 1x1 overlay at origin row 2, column 3 -> pixel (row 1, column 2).
        let file = Self.file(values: [UInt16](repeating: 0, count: 12), rows: 3) { ds in
            ds.setUInt16(1, for: Tag(group: 0x6000, element: 0x0010))
            ds.setUInt16(1, for: Tag(group: 0x6000, element: 0x0011))
            ds.setString("G", for: Tag(group: 0x6000, element: 0x0040), vr: .CS)
            ds[Tag(group: 0x6000, element: 0x0050)] = DataElement.data(
                tag: Tag(group: 0x6000, element: 0x0050), vr: .SS, data: Data([2, 0, 3, 0]))
            ds.setUInt16(1, for: Tag(group: 0x6000, element: 0x0100))
            ds.setUInt16(0, for: Tag(group: 0x6000, element: 0x0102))
            ds[Tag(group: 0x6000, element: 0x3000)] = DataElement.data(
                tag: Tag(group: 0x6000, element: 0x3000), vr: .OW, data: Data([1, 0]))
        }
        let renderer = TerminalRenderer(dicomFile: file)
        let plain = try renderer.extractPixels(windowCenter: 100, windowWidth: 10)
        XCTAssertEqual(plain.pixels.max(), 0)
        let drawn = try renderer.extractPixels(windowCenter: 100, windowWidth: 10, showOverlays: true)
        XCTAssertEqual(drawn.pixels.firstIndex(of: 1), 1 * 4 + 2)
        XCTAssertEqual(drawn.pixels.filter { $0 == 1 }.count, 1)
    }

    // MARK: - Frame numbers and labels

    func testThumbnailLabelsAreFrameNumbers() throws {
        let renderer = TerminalRenderer(dicomFile: Self.file(values: [0, 10, 20, 30], frames: 2))
        let grid = try renderer.renderThumbnailGrid(frames: [0, 1], mode: .ascii,
                                                    terminalSize: TerminalSize(width: 80, height: 24))
        XCTAssertTrue(grid.contains("Frame number 1"), grid)
        XCTAssertTrue(grid.contains("Frame number 2"), grid)
        XCTAssertFalse(grid.contains("Frame 0") || grid.contains("Frame number 0"))
        XCTAssertEqual(ViewerError.frameNotAvailable(4).description, "Frame number 5 is not available")
    }

    func testInfoLabelsArePS36Names() {
        let file = Self.file(values: [0], window: (40.5, 400)) { ds in
            ds.setString("DOE^JANE", for: .patientName, vr: .PN)
            ds.setString("ID1", for: .patientID, vr: .LO)
            ds.setString("F", for: .patientSex, vr: .CS)
            ds.setString("HEAD", for: .studyDescription, vr: .LO)
            ds.setString("20260101", for: .studyDate, vr: .DA)
            ds.setString("CT", for: .modality, vr: .CS)
        }
        let info = TerminalRenderer(dicomFile: file).generateInfoOverlay()
        for label in ["Patient's Name: DOE^JANE", "Patient ID: ID1", "Patient's Sex: F",
                      "Study Description: HEAD", "Study Date: 20260101", "Modality: CT",
                      "Bits Stored: 12", "Window Center: 40.5", "Window Width: 400"] {
            XCTAssertTrue(info.contains(label), label)
        }
        XCTAssertFalse(info.contains("W/L:"))
    }

    // MARK: - Option checks

    func testWindowAndFrameOptionChecks() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("viewer-\(UUID().uuidString).dcm")
        try Self.file(values: [0]).write().write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let path = url.path
        XCTAssertThrowsError(try DICOMViewer.parse([path, "--window-center", "40", "--window-width", "0.5"]))
        XCTAssertNoThrow(try DICOMViewer.parse([path, "--window-center", "40", "--window-width", "0.5",
                                                "--voi-lut-function", "LINEAR_EXACT"]))
        XCTAssertThrowsError(try DICOMViewer.parse([path, "--window-center", "40", "--window-width", "0",
                                                    "--voi-lut-function", "SIGMOID"]))
        XCTAssertThrowsError(try DICOMViewer.parse([path, "--voi-lut-function", "LOG"]))
        XCTAssertThrowsError(try DICOMViewer.parse([path, "--frame-number", "0"]))
        // Both given: refused in run() with exit 1 (P-VIEWER-FRAME)
        var both = try DICOMViewer.parse([path, "--frame", "1", "--frame-number", "2"])
        XCTAssertThrowsError(try both.run()) { error in
            XCTAssertEqual(DICOMViewer.exitCode(for: error).rawValue, 1)
        }
        let viewer = try DICOMViewer.parse([path, "--frame-number", "3"])
        XCTAssertEqual(viewer.frameIndex, 2)
        XCTAssertNil(viewer.frameDeprecationNote)
        XCTAssertEqual(try DICOMViewer.parse([path]).frameIndex, 0)
        let old = try DICOMViewer.parse([path, "--frame", "3"])
        XCTAssertEqual(old.frameIndex, 3)
        XCTAssertEqual(old.frameDeprecationNote, "Note: --frame is deprecated (0-based index); use --frame-number 4")
        XCTAssertThrowsError(try DICOMViewer.parse([path, "--frame", "-1"]))
    }
}
