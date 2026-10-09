import XCTest
@testable import DICOMKit
import DICOMCore
#if canImport(CoreGraphics)
import CoreGraphics
#endif

/// Regression: dicom-export must window an image the same way the on-screen viewer
/// does. Both apply the file's VOI Window Center/Width after the Modality LUT /
/// Rescale Slope/Intercept (PS3.3 C.11.2.1.2.1). A CT with a non-zero Rescale
/// Intercept previously exported washed-out / near-blank because the HU window was
/// applied directly to stored values. The deprecated stored-unit
/// `determineWindowSettings` is still pinned here (its callers in DICOMStudio consume
/// it until that module is rewired to `determineModalityWindow`, A6 / D65).
final class ExportWindowParityTests: XCTestCase {

    /// 32×32 16-bit MONOCHROME2 CT-like frame with Rescale Intercept −1024,
    /// Window Center 40 / Width 400 (HU), and a gradient of stored values.
    private func ctElements() -> [DataElement] {
        var els: [DataElement] = []
        els.append(.uint16(tag: .rows, value: 32))
        els.append(.uint16(tag: .columns, value: 32))
        els.append(.uint16(tag: .bitsAllocated, value: 16))
        els.append(.uint16(tag: .bitsStored, value: 16))
        els.append(.uint16(tag: .highBit, value: 15))
        els.append(.uint16(tag: .pixelRepresentation, value: 0))
        els.append(.uint16(tag: .samplesPerPixel, value: 1))
        els.append(.string(tag: .photometricInterpretation, vr: .CS, value: "MONOCHROME2"))
        els.append(.string(tag: .rescaleIntercept, vr: .DS, value: "-1024"))
        els.append(.string(tag: .rescaleSlope, vr: .DS, value: "1"))
        els.append(.string(tag: .windowCenter, vr: .DS, value: "40"))
        els.append(.string(tag: .windowWidth, vr: .DS, value: "400"))
        els.append(.string(tag: .sopClassUID, vr: .UI, value: "1.2.840.10008.5.1.4.1.1.2"))
        els.append(.string(tag: .sopInstanceUID, vr: .UI, value: "1.2.3.4.5.6.7.8.9"))
        var pixels = Data()
        for i in 0..<(32 * 32) {
            let v = UInt16((i * 60) % 4096)   // stored values 0..4095 (HU −1024..3071)
            pixels.append(UInt8(v & 0xFF)); pixels.append(UInt8((v >> 8) & 0xFF))
        }
        els.append(DataElement(tag: .pixelData, vr: .OW, length: UInt32(pixels.count), valueData: pixels))
        return els
    }

    private func makeFile() throws -> DICOMFile {
        let data = try DICOMFile.create(dataSet: DataSet(elements: ctElements()),
                                        transferSyntaxUID: TransferSyntax.explicitVRLittleEndian.uid).write()
        return try DICOMFile.read(from: data)
    }

    /// determineWindowSettings converts the HU window (40/400) to stored space using
    /// the −1024 intercept → center 1064, width 400.
    @available(*, deprecated)
    func testWindowConvertedToStoredSpace() throws {
        let file = try makeFile()
        let pd = try XCTUnwrap(file.pixelData())

        let fromFile = DICOMImageExporter.determineWindowSettings(
            from: file, pixelData: pd, frameIndex: 0, windowCenter: nil, windowWidth: nil)
        XCTAssertEqual(fromFile.center, 1064, accuracy: 0.001, "file VOI window must be rescaled HU→stored")
        XCTAssertEqual(fromFile.width, 400, accuracy: 0.001)

        // Explicit HU values are likewise converted to stored space.
        let explicit = DICOMImageExporter.determineWindowSettings(
            from: file, pixelData: pd, frameIndex: 0, windowCenter: 40, windowWidth: 400)
        XCTAssertEqual(explicit.center, 1064, accuracy: 0.001)
        XCTAssertEqual(explicit.width, 400, accuracy: 0.001)
    }

    /// A CT that declares two VOI pairs in one multi-valued element (a lung and a
    /// soft-tissue window, `-600\50` / `1200\350`) must present at the first pair.
    /// `windowSettings()` parses only a single DS and returns nil for these files,
    /// so reading it alone silently discarded the VOI and auto-stretched the full
    /// pixel range instead — a flat render that disagreed with the viewer.
    @available(*, deprecated)
    func testFirstOfSeveralWindowsIsUsed() throws {
        var els = ctElements().filter { $0.tag != .windowCenter && $0.tag != .windowWidth }
        els.append(.string(tag: .windowCenter, vr: .DS, value: "-600\\50"))
        els.append(.string(tag: .windowWidth, vr: .DS, value: "1200\\350"))
        let data = try DICOMFile.create(dataSet: DataSet(elements: els),
                                        transferSyntaxUID: TransferSyntax.explicitVRLittleEndian.uid).write()
        let file = try DICOMFile.read(from: data)
        let pd = try XCTUnwrap(file.pixelData())

        XCTAssertNil(file.windowSettings(), "precondition: the single-DS accessor cannot read a multi-valued VOI")

        let window = DICOMImageExporter.determineWindowSettings(
            from: file, pixelData: pd, frameIndex: 0, windowCenter: nil, windowWidth: nil)
        // −600 HU through the −1024 intercept → stored 424.
        XCTAssertEqual(window.center, 424, accuracy: 0.001, "the first VOI pair is the default presentation")
        XCTAssertEqual(window.width, 1200, accuracy: 0.001)
    }

    /// The exported raster (default + apply-window) must equal the viewer's render
    /// (file VOI window in modality units, applied after the rescale — D243).
    func testExportMatchesViewerRender() throws {
        #if canImport(CoreGraphics)
        let file = try makeFile()
        let pd = try XCTUnwrap(file.pixelData())
        let viewerWindow = try XCTUnwrap(file.windowSettings())

        let viewer = try XCTUnwrap(file.renderFrame(0, window: viewerWindow))
        let exportDefault = try DICOMImageExporter.renderFrameForExport(
            file: file, pixelData: pd, frameIndex: 0, applyWindow: false, windowCenter: nil, windowWidth: nil)
        let exportApply = try DICOMImageExporter.renderFrameForExport(
            file: file, pixelData: pd, frameIndex: 0, applyWindow: true, windowCenter: nil, windowWidth: nil)

        XCTAssertEqual(rgba(viewer), rgba(exportDefault),
                       "export (default) must match the viewer's VOI-windowed render")
        XCTAssertEqual(rgba(viewer), rgba(exportApply),
                       "export (--apply-window) must match the viewer's VOI-windowed render")
        // Sanity: the windowed render is high-contrast, not a near-blank clip.
        XCTAssertGreaterThan(distinct(rgba(viewer)), 10)
        #endif
    }

    #if canImport(CoreGraphics)
    private func rgba(_ img: CGImage?) -> [UInt8] {
        guard let img, let cg = img.copy(), let p = cg.dataProvider, let px = p.data else { return [] }
        let len = CFDataGetLength(px); let ptr = CFDataGetBytePtr(px)!
        return Array(UnsafeBufferPointer(start: ptr, count: len))
    }
    private func distinct(_ b: [UInt8]) -> Int {
        var s = Set<UInt8>(); var i = 0; while i + 2 < b.count { s.insert(b[i]); i += 4 }; return s.count
    }
    #endif
}
