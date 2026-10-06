import XCTest
import DICOMCore
@testable import DICOMKit
@testable import dicom_export
#if canImport(CoreGraphics)
import CoreGraphics
#endif

/// `dicom-export` against DICOM 2026a: the cine frame rate of PS3.3 Table C.7-13, Burned In
/// Annotation (0028,0301) of Table C.7-9, frame selection, and one render path (the
/// PS3.4 N.2 chain) for every subcommand. Names and tags dumped from the DocBook by script.
final class ExportStandardTests: XCTestCase {

    private func dataSet(_ elements: [DataElement]) -> DataSet { DataSet(elements: elements) }

    // MARK: - Cine frame rate (PS3.3 Table C.7-13)

    func testFPSOptionWinsOverTheFile() {
        let ds = dataSet([.string(tag: .recommendedDisplayFrameRate, vr: .IS, value: "30")])
        XCTAssertEqual(DICOMImageExporter.CineFrameRate.resolve(explicit: 15, dataSet: ds),
                       DICOMImageExporter.CineFrameRate(fps: 15, source: .option))
    }

    func testRecommendedDisplayFrameRateComesFirst() {
        let ds = dataSet([
            .string(tag: .recommendedDisplayFrameRate, vr: .IS, value: "30"),
            .string(tag: .cineRate, vr: .IS, value: "25"),
            .string(tag: .frameTime, vr: .DS, value: "100"),
        ])
        XCTAssertEqual(DICOMImageExporter.CineFrameRate.resolve(explicit: nil, dataSet: ds),
                       DICOMImageExporter.CineFrameRate(fps: 30, source: .recommendedDisplayFrameRate))
    }

    func testCineRateBeforeFrameTime() {
        let ds = dataSet([
            .string(tag: .cineRate, vr: .IS, value: "25"),
            .string(tag: .frameTime, vr: .DS, value: "100"),
        ])
        XCTAssertEqual(DICOMImageExporter.CineFrameRate.resolve(explicit: nil, dataSet: ds),
                       DICOMImageExporter.CineFrameRate(fps: 25, source: .cineRate))
    }

    /// Frame Time (0018,1063) is in msec (C.7.6.5.1.1): 40 ms per frame is 25 frames/s.
    func testFrameTimeIsMillisecondsPerFrame() {
        let ds = dataSet([.string(tag: .frameTime, vr: .DS, value: "40")])
        let rate = DICOMImageExporter.CineFrameRate.resolve(explicit: nil, dataSet: ds)
        XCTAssertEqual(rate.source, .frameTime)
        XCTAssertEqual(rate.fps, 25, accuracy: 1e-9)
    }

    /// Frame Time may be 0 for a single frame (C.7.6.5.1.1); zero and non-numbers are skipped.
    func testZeroOrInvalidValuesFallBackToTen() {
        let ds = dataSet([
            .string(tag: .recommendedDisplayFrameRate, vr: .IS, value: "0"),
            .string(tag: .cineRate, vr: .IS, value: "abc"),
            .string(tag: .frameTime, vr: .DS, value: "0"),
        ])
        XCTAssertEqual(DICOMImageExporter.CineFrameRate.resolve(explicit: nil, dataSet: ds),
                       DICOMImageExporter.CineFrameRate(fps: 10, source: .fallback))
        XCTAssertEqual(DICOMImageExporter.CineFrameRate.resolve(explicit: nil, dataSet: dataSet([])).fps, 10)
    }

    func testSourceLabelsAreTheTable6_1Names() {
        XCTAssertEqual(DICOMImageExporter.CineFrameRate.Source.recommendedDisplayFrameRate.label, "Recommended Display Frame Rate (0008,2144)")
        XCTAssertEqual(DICOMImageExporter.CineFrameRate.Source.cineRate.label, "Cine Rate (0018,0040)")
        XCTAssertEqual(DICOMImageExporter.CineFrameRate.Source.frameTime.label, "Frame Time (0018,1063)")
    }

    func testAnimateFPSIsOptionalAndHelpNamesTheAttributes() throws {
        let cmd = try DICOMExport.Animate.parse(["cine.dcm", "--output", "cine.gif"])
        XCTAssertNil(cmd.fps, "no --fps: the rate comes from the file")
        let help = DICOMExport.Animate.helpMessage(columns: 400)
        for name in ["Recommended Display Frame Rate (0008,2144)", "Cine Rate (0018,0040)", "Frame Time (0018,1063)"] {
            XCTAssertTrue(help.contains(name), name)
        }
    }

    // MARK: - Burned In Annotation (0028,0301), Enumerated Values YES / NO

    func testBurnedInAnnotation() {
        XCTAssertTrue(DICOMImageExporter.BurnedInAnnotation.isYes(dataSet([.string(tag: .burnedInAnnotation, vr: .CS, value: "YES")])))
        XCTAssertTrue(DICOMImageExporter.BurnedInAnnotation.isYes(dataSet([.string(tag: .burnedInAnnotation, vr: .CS, value: "YES ")])))
        XCTAssertFalse(DICOMImageExporter.BurnedInAnnotation.isYes(dataSet([.string(tag: .burnedInAnnotation, vr: .CS, value: "NO")])))
        XCTAssertFalse(DICOMImageExporter.BurnedInAnnotation.isYes(dataSet([])), "absent: may or may not, no warning")
        XCTAssertTrue(DICOMImageExporter.BurnedInAnnotation.warning(for: "a.dcm").contains("Burned In Annotation (0028,0301) is YES"))
    }

    // MARK: - Frame numbers from 1 (P-EXPORT-1; PS3.3 Table 10-3); the 0-based options are deprecated

    func testFrameOptionsSayZeroBased() {
        XCTAssertTrue(DICOMExport.Single.helpMessage(columns: 400).contains("--frame <frame>         deprecated: 0-based index")
                      || DICOMExport.Single.helpMessage(columns: 400).contains("deprecated: 0-based index; use --frame-number"))
        XCTAssertTrue(DICOMExport.Animate.helpMessage(columns: 400).contains("First frame, Frame number from 1"))
    }

    func testWindowOptionsNameTheAttributes() {
        let help = DICOMExport.Single.helpMessage(columns: 400)
        XCTAssertTrue(help.contains("Window Center (0028,1050) in modality units"))
        XCTAssertTrue(help.contains("Window Width (0028,1051) in modality units"))
        XCTAssertTrue(help.contains("VOI LUT Sequence (0028,3010)"))
    }

    // MARK: - One render path

    /// 16×16 MONOCHROME2 CT-like frame: Rescale Intercept −1024, Window Center 40 / Width 400 (HU).
    private func ctFile() throws -> DICOMFile {
        var els: [DataElement] = [
            .uint16(tag: .rows, value: 16), .uint16(tag: .columns, value: 16),
            .uint16(tag: .bitsAllocated, value: 16), .uint16(tag: .bitsStored, value: 16),
            .uint16(tag: .highBit, value: 15), .uint16(tag: .pixelRepresentation, value: 0),
            .uint16(tag: .samplesPerPixel, value: 1),
            .string(tag: .photometricInterpretation, vr: .CS, value: "MONOCHROME2"),
            .string(tag: .rescaleIntercept, vr: .DS, value: "-1024"),
            .string(tag: .rescaleSlope, vr: .DS, value: "1"),
            .string(tag: .windowCenter, vr: .DS, value: "40"),
            .string(tag: .windowWidth, vr: .DS, value: "400"),
            .string(tag: .sopClassUID, vr: .UI, value: "1.2.840.10008.5.1.4.1.1.2"),
            .string(tag: .sopInstanceUID, vr: .UI, value: "1.2.3.4.5.6.7.8.9"),
        ]
        var pixels = Data()
        for i in 0..<(16 * 16) {
            let v = UInt16((i * 16) % 4096)
            pixels.append(UInt8(v & 0xFF)); pixels.append(UInt8(v >> 8))
        }
        els.append(DataElement(tag: .pixelData, vr: .OW, length: UInt32(pixels.count), valueData: pixels))
        let data = try DICOMFile.create(dataSet: DataSet(elements: els),
                                        transferSyntaxUID: TransferSyntax.explicitVRLittleEndian.uid).write()
        return try DICOMFile.read(from: data)
    }

    #if canImport(CoreGraphics)
    private func bytes(_ image: CGImage?) -> [UInt8] {
        guard let image, let data = image.dataProvider?.data, let ptr = CFDataGetBytePtr(data) else { return [] }
        return Array(UnsafeBufferPointer(start: ptr, count: CFDataGetLength(data)))
    }

    /// contact-sheet now renders like `single`: the HU window applied after the rescale
    /// (PS3.3 C.11.2.1.2.1). The old stored-window path applied 40/400 to stored values.
    func testContactSheetFrameEqualsSingleExport() throws {
        let file = try ctFile()
        let pd = try XCTUnwrap(file.pixelData())
        let single = try DICOMImageExporter.renderFrameForExport(
            file: file, pixelData: pd, frameIndex: 0, applyWindow: false, windowCenter: nil, windowWidth: nil)
        let sheet = try ExportFrames.render(file: file, frameIndex: 0, applyWindow: false, windowCenter: nil, windowWidth: nil)
        XCTAssertEqual(bytes(sheet), bytes(single))
        // D243 (2026-10-06): the DICOMFile stored-window path applies the window after the
        // rescale too, so it now renders the same raster (it ignored Rescale Intercept before).
        let storedWindowPath = try file.tryRenderFrameWithStoredWindow(0)
        XCTAssertEqual(bytes(storedWindowPath), bytes(single), "the stored-window path applies the window after the rescale (D243)")
    }

    /// animate with --apply-window and explicit values renders like `single` does.
    func testAnimateFrameEqualsSingleExportWithExplicitWindow() throws {
        let file = try ctFile()
        let pd = try XCTUnwrap(file.pixelData())
        let single = try DICOMImageExporter.renderFrameForExport(
            file: file, pixelData: pd, frameIndex: 0, applyWindow: true, windowCenter: -600, windowWidth: 1500)
        let frame = try ExportFrames.render(file: file, pixelData: pd, frameIndex: 0,
                                            applyWindow: true, windowCenter: -600, windowWidth: 1500)
        XCTAssertEqual(bytes(frame), bytes(single))
    }
    #endif
}
