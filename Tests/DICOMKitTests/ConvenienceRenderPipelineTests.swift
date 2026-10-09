// NEMA-verified: 2026a, checked 2026-10-06 — the window is applied "after any Modality LUT or Rescale Slope and Intercept specified in the IOD have been applied" (PS3.3 2026a C.11.2.1.2.1; chain order PS3.4 2026a N.2); MONOCHROME1 is "displayed as white after any VOI gray scale transformations" (C.7.6.3.1.2); the first Window Center value is the default presentation (C.11.2.1.2); the full-range window x1…x2 is C.11.2.1.2.1's (D243, A6 / D65)
import XCTest
@testable import DICOMKit
import DICOMCore
#if canImport(CoreGraphics)
import CoreGraphics
#endif

/// D243: the convenience renderers of `DICOMFile` (`renderFrame(_:window:)`,
/// `renderFrameWithStoredWindow`, `tryRenderFrameWithStoredWindow`) apply the header's
/// Window Center / Width through `GrayscaleDisplayPipeline`, i.e. after the Modality LUT,
/// where PS3.3 C.11.2.1.2.1 places it — the same bytes as the export chain. The old
/// result (header window applied to stored values, misplaced by the Rescale Intercept)
/// is pinned as wrong.
///
/// A6 / D65: `DICOMImageExporter.determineModalityWindow` returns the window in the units
/// the renderers apply (modality units), exactly, for any slope; the stored-unit
/// `determineWindowSettings` is deprecated.
final class ConvenienceRenderPipelineTests: XCTestCase {

    // MARK: - Fixture

    /// 32×32 16-bit CT-like frame: stored 0…4092 in steps of 4, Rescale Intercept −1024 (HU −1024…3068),
    /// Window Center 40 / Width 400 (HU) unless `window` is nil.
    private func ctElements(photometric: String = "MONOCHROME2", slope: String = "1",
                            intercept: String = "-1024", window: (String, String)? = ("40", "400")) -> [DataElement] {
        var els: [DataElement] = []
        els.append(.uint16(tag: .rows, value: 32))
        els.append(.uint16(tag: .columns, value: 32))
        els.append(.uint16(tag: .bitsAllocated, value: 16))
        els.append(.uint16(tag: .bitsStored, value: 16))
        els.append(.uint16(tag: .highBit, value: 15))
        els.append(.uint16(tag: .pixelRepresentation, value: 0))
        els.append(.uint16(tag: .samplesPerPixel, value: 1))
        els.append(.string(tag: .photometricInterpretation, vr: .CS, value: photometric))
        els.append(.string(tag: .rescaleIntercept, vr: .DS, value: intercept))
        els.append(.string(tag: .rescaleSlope, vr: .DS, value: slope))
        if let window {
            els.append(.string(tag: .windowCenter, vr: .DS, value: window.0))
            els.append(.string(tag: .windowWidth, vr: .DS, value: window.1))
        }
        els.append(.string(tag: .sopClassUID, vr: .UI, value: "1.2.840.10008.5.1.4.1.1.2"))
        els.append(.string(tag: .sopInstanceUID, vr: .UI, value: "1.2.3.4.5.6.7.8.9"))
        var pixels = Data()
        for i in 0..<(32 * 32) {
            let v = UInt16((i * 4) % 4096)
            pixels.append(UInt8(v & 0xFF)); pixels.append(UInt8((v >> 8) & 0xFF))
        }
        els.append(DataElement(tag: .pixelData, vr: .OW, length: UInt32(pixels.count), valueData: pixels))
        return els
    }

    private func makeFile(_ els: [DataElement]) throws -> DICOMFile {
        let data = try DICOMFile.create(dataSet: DataSet(elements: els),
                                        transferSyntaxUID: TransferSyntax.explicitVRLittleEndian.uid).write()
        return try DICOMFile.read(from: data)
    }

    #if canImport(CoreGraphics)
    private func bytes(_ image: CGImage?) throws -> [UInt8] {
        let image = try XCTUnwrap(image)
        let data = try XCTUnwrap(image.dataProvider?.data)
        let count = CFDataGetLength(data)
        let ptr = try XCTUnwrap(CFDataGetBytePtr(data))
        return Array(UnsafeBufferPointer(start: ptr, count: count))
    }

    // MARK: - D243

    /// The convenience path renders the same bytes as the export chain, and as the pipeline.
    func testStoredWindowRendersThroughTheChainLikeExport() throws {
        let file = try makeFile(ctElements())
        let pd = try XCTUnwrap(file.pixelData())

        let convenience = try bytes(file.renderFrameWithStoredWindow(0))
        let throwing = try bytes(try file.tryRenderFrameWithStoredWindow(0))
        let explicit = try bytes(file.renderFrame(0, window: WindowSettings(center: 40, width: 400)))
        let export = try bytes(try DICOMImageExporter.renderFrameForExport(
            file: file, pixelData: pd, frameIndex: 0, applyWindow: false, windowCenter: nil, windowWidth: nil))
        let pipeline = DICOMImageExporter.determineDisplayPipeline(
            from: file, pixelData: pd, frameIndex: 0, windowCenter: nil, windowWidth: nil)
        let direct = try bytes(PixelDataRenderer(pixelData: pd).renderMonochromeFrame(0, pipeline: pipeline))

        XCTAssertEqual(convenience, export, "renderFrameWithStoredWindow must place the window after the rescale (C.11.2.1.2.1)")
        XCTAssertEqual(throwing, export)
        XCTAssertEqual(explicit, export, "renderFrame(_:window:) takes the window in modality units")
        XCTAssertEqual(direct, export)
        // HU 40/400 over stored 0…4092 (HU −1024…3068): the window spans stored 864…1264,
        // so the ramp is 400 wide inside a 4096 gradient — black, a ramp, then white.
        XCTAssertEqual(convenience.first, 0)
        XCTAssertEqual(convenience.last, 255)
        XCTAssertGreaterThan(Set(convenience).count, 100)
    }

    /// The pre-D243 result — the HU window applied to stored values — is a different,
    /// washed-out raster: with centre 40 on stored 0…4092 almost every pixel is white.
    func testTheOldMisplacedWindowIsNotWhatTheConveniencePathRenders() throws {
        let file = try makeFile(ctElements())
        let pd = try XCTUnwrap(file.pixelData())
        let misplaced = try bytes(PixelDataRenderer(pixelData: pd)
            .renderMonochromeFrame(0, window: WindowSettings(center: 40, width: 400)))
        let correct = try bytes(file.renderFrameWithStoredWindow(0))
        XCTAssertNotEqual(misplaced, correct)
        let white = misplaced.filter { $0 == 255 }.count
        XCTAssertGreaterThan(white, misplaced.count * 9 / 10, "the misplaced window clips nearly the whole frame to white")
        XCTAssertLessThan(correct.filter { $0 == 255 }.count, correct.count * 3 / 4)
    }

    /// MONOCHROME1 keeps its INVERSE Presentation LUT after the window (C.7.6.3.1.2).
    func testMonochrome1IsInvertedAfterTheWindow() throws {
        let m2 = try bytes(try makeFile(ctElements()).renderFrameWithStoredWindow(0))
        let m1 = try bytes(try makeFile(ctElements(photometric: "MONOCHROME1")).renderFrameWithStoredWindow(0))
        // INVERSE is applied in the chain before quantisation (PS3.4 N.2), so a byte may differ
        // from 255 − the MONOCHROME2 byte by the rounding step.
        XCTAssertEqual(m1.count, m2.count)
        XCTAssertLessThanOrEqual(zip(m1, m2).map { abs(Int($0) - (255 - Int($1))) }.max() ?? 0, 1)
        XCTAssertEqual(m1.first, 255)
        XCTAssertEqual(m1.last, 0)
        // and it is the export chain's raster
        let m1File = try makeFile(ctElements(photometric: "MONOCHROME1"))
        let pd = try XCTUnwrap(m1File.pixelData())
        XCTAssertEqual(m1, try bytes(try DICOMImageExporter.renderFrameForExport(
            file: m1File, pixelData: pd, frameIndex: 0, applyWindow: false, windowCenter: nil, windowWidth: nil)))
    }

    /// The first of several Window Center values is the default presentation (C.11.2.1.2);
    /// `windowSettings()` alone cannot read a multi-valued pair, so the convenience path
    /// used to fall back to auto-windowing on such a CT.
    func testFirstOfSeveralHeaderWindowsIsUsed() throws {
        let file = try makeFile(ctElements(window: ("-600\\40", "1200\\400")))
        XCTAssertNil(file.windowSettings(), "precondition: the single-DS accessor cannot read a multi-valued VOI")
        let pd = try XCTUnwrap(file.pixelData())
        let convenience = try bytes(file.renderFrameWithStoredWindow(0))
        let lung = try bytes(file.renderFrame(0, window: WindowSettings(center: -600, width: 1200)))
        let export = try bytes(try DICOMImageExporter.renderFrameForExport(
            file: file, pixelData: pd, frameIndex: 0, applyWindow: false, windowCenter: nil, windowWidth: nil))
        XCTAssertEqual(convenience, lung)
        XCTAssertEqual(convenience, export)
    }

    /// A Modality LUT Sequence is applied before the window too (C.11.1.1.2: it wins over
    /// the rescale pair), through `DICOMFile.modalityLUT(frameIndex:)`.
    func testModalityLUTSequenceIsAppliedBeforeTheWindow() throws {
        // The table halves every stored value (output 0…2047, unsigned as a table-form
        // Modality LUT is), the same as Rescale Slope 0.5 / Intercept 0.
        var els = ctElements(slope: "1", intercept: "0", window: ("500", "1000"))
        var descriptor = Data()
        for v in [UInt16(4096), UInt16(0), UInt16(16)] {
            descriptor.append(UInt8(v & 0xFF)); descriptor.append(UInt8(v >> 8))
        }
        var table = Data()
        for stored in 0..<4096 {
            let v = UInt16(stored / 2)
            table.append(UInt8(v & 0xFF)); table.append(UInt8(v >> 8))
        }
        let item = SequenceItem(elements: [
            DataElement(tag: .lutDescriptor, vr: .US, length: UInt32(descriptor.count), valueData: descriptor),
            DataElement(tag: .lutData, vr: .OW, length: UInt32(table.count), valueData: table),
        ])
        var dataSet = DataSet(elements: els)
        dataSet.setSequence([item], for: .modalityLUTSequence)
        els = Array(dataSet)
        let file = try makeFile(els)
        guard case .lut? = file.modalityLUT(frameIndex: 0) else {
            return XCTFail("the Modality LUT Sequence must be the frame's Modality LUT")
        }
        let withTable = try bytes(file.renderFrameWithStoredWindow(0))
        let withRescale = try bytes(try makeFile(ctElements(slope: "0.5", intercept: "0", window: ("500", "1000")))
            .renderFrameWithStoredWindow(0))
        XCTAssertEqual(withTable, withRescale, "a table equal to the rescale renders the same bytes")
        XCTAssertGreaterThan(Set(withTable).count, 100)
    }
    #endif

    func testModalityLUTPrefersTheSequenceAndIsNilForTheIdentity() throws {
        XCTAssertNil(try makeFile(ctElements(slope: "1", intercept: "0")).modalityLUT(frameIndex: 0))
        guard case .rescale(let slope, let intercept, _)? = try makeFile(ctElements()).modalityLUT(frameIndex: 0) else {
            return XCTFail("a rescale pair other than 1 / 0 is the frame's Modality LUT")
        }
        XCTAssertEqual(slope, 1)
        XCTAssertEqual(intercept, -1024)
    }

    // MARK: - A6 / D65: the exact window

    /// The explicit and header windows come back unchanged in modality units, for any slope.
    func testDetermineModalityWindowIsExactForAnySlope() throws {
        for slope in ["1", "2", "0.5", "-1"] {
            let file = try makeFile(ctElements(slope: slope))
            let pd = try XCTUnwrap(file.pixelData())
            let header = DICOMImageExporter.determineModalityWindow(
                from: file, pixelData: pd, frameIndex: 0, windowCenter: nil, windowWidth: nil)
            XCTAssertEqual(header.center, 40, "slope \(slope)")
            XCTAssertEqual(header.width, 400, "slope \(slope)")
            let explicit = DICOMImageExporter.determineModalityWindow(
                from: file, pixelData: pd, frameIndex: 0, windowCenter: -600, windowWidth: 1200)
            XCTAssertEqual(explicit.center, -600)
            XCTAssertEqual(explicit.width, 1200)
            #if canImport(CoreGraphics)
            // Rendering with the returned window is the export chain's raster.
            let viaWindow = try bytes(file.renderFrame(0, window: header))
            let export = try bytes(try DICOMImageExporter.renderFrameForExport(
                file: file, pixelData: pd, frameIndex: 0, applyWindow: false, windowCenter: nil, windowWidth: nil))
            XCTAssertEqual(viaWindow, export, "slope \(slope)")
            #endif
        }
    }

    /// The deprecated stored-unit conversion is what the Studio call sites still consume:
    /// pinned, so the rewiring can see the two differ by the rescale.
    @available(*, deprecated)
    func testDeprecatedStoredUnitWindowDiffersByTheRescale() throws {
        let file = try makeFile(ctElements(slope: "2", intercept: "-1024"))
        let pd = try XCTUnwrap(file.pixelData())
        let stored = DICOMImageExporter.determineWindowSettings(
            from: file, pixelData: pd, frameIndex: 0, windowCenter: nil, windowWidth: nil)
        XCTAssertEqual(stored.center, (40 + 1024) / 2)
        XCTAssertEqual(stored.width, 200)
        let modality = DICOMImageExporter.determineModalityWindow(
            from: file, pixelData: pd, frameIndex: 0, windowCenter: nil, windowWidth: nil)
        XCTAssertEqual(modality.center, 40)
        XCTAssertEqual(modality.width, 400)
    }

    /// With no header window the fallback is C.11.2.1.2.1's full-range window over the
    /// frame's modality values: the fixture's stored 0…4092 through −1024 is HU −1024…3068.
    func testFullRangeFallbackIsInModalityUnits() throws {
        let file = try makeFile(ctElements(window: nil))
        let pd = try XCTUnwrap(file.pixelData())
        let window = DICOMImageExporter.determineModalityWindow(
            from: file, pixelData: pd, frameIndex: 0, windowCenter: nil, windowWidth: nil)
        XCTAssertEqual(window.center, (-1024.0 + 3068.0) / 2)
        XCTAssertEqual(window.width, 4092)
        XCTAssertEqual(window.function, .linearExact)
        #if canImport(CoreGraphics)
        let rendered = try bytes(file.renderFrame(0, window: window))
        XCTAssertEqual(rendered.first, 0)
        XCTAssertEqual(rendered.last, 255, "x2 is white")
        XCTAssertGreaterThan(Set(rendered).count, 200)
        #endif
    }
}
