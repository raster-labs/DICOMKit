import XCTest
import Foundation
@testable import DICOMKit
@testable import DICOMCore
#if canImport(CoreGraphics)
import CoreGraphics
#endif

/// Regression tests for `PixelEditor` operating on compressed (encapsulated) sources.
///
/// A compressed Pixel Data element holds a fragmented/compressed bitstream, not a flat
/// pixel array. Editing those bytes in place corrupts the bitstream, and the result —
/// still tagged as the compressed transfer syntax — cannot be decoded by a viewer such
/// as Horos, so the image fails to display. `PixelEditor` must therefore decode such a
/// source to native pixels and emit uncompressed Explicit VR Little Endian.
final class PixelEditorTests: XCTestCase {

    /// Builds a minimal single-frame 16-bit MONOCHROME2 image with sequential pixels.
    private func makeUncompressed(rows: Int = 8, columns: Int = 8) -> DICOMFile {
        var ds = DataSet()
        ds.setString("1.2.840.10008.5.1.4.1.1.2", for: .sopClassUID, vr: .UI)
        ds.setString("1.2.3.4.5.6.7.8.9", for: .sopInstanceUID, vr: .UI)
        ds.setString("1.2.3.4.5.100", for: .studyInstanceUID, vr: .UI)
        ds.setString("1.2.3.4.5.200", for: .seriesInstanceUID, vr: .UI)
        ds.setString("CT", for: .modality, vr: .CS)
        ds.setString("MONOCHROME2", for: .photometricInterpretation, vr: .CS)
        ds.setUInt16(UInt16(rows), for: .rows)
        ds.setUInt16(UInt16(columns), for: .columns)
        ds.setUInt16(16, for: .bitsAllocated)
        ds.setUInt16(16, for: .bitsStored)
        ds.setUInt16(15, for: .highBit)
        ds.setUInt16(0, for: .pixelRepresentation)
        ds.setUInt16(1, for: .samplesPerPixel)
        var px = Data()
        for i in 0..<(rows * columns) {
            let v = UInt16(i % 256)
            px.append(UInt8(v & 0xFF)); px.append(UInt8(v >> 8))
        }
        ds[.pixelData] = DataElement.data(tag: .pixelData, vr: .OW, data: px)
        return DICOMFile.create(
            dataSet: ds,
            sopClassUID: "1.2.840.10008.5.1.4.1.1.2",
            transferSyntaxUID: TransferSyntax.explicitVRLittleEndian.uid
        )
    }

    /// Builds a multi-frame 16-bit MONOCHROME2 image where every pixel of frame `f`
    /// holds the constant value `f + 1`, so per-frame edits are trivial to assert.
    private func makeMultiFrame(rows: Int = 4, columns: Int = 4, frames: Int = 3) -> DICOMFile {
        var ds = DataSet()
        ds.setString("1.2.840.10008.5.1.4.1.1.2", for: .sopClassUID, vr: .UI)
        ds.setString("1.2.3.4.5.6.7.8.10", for: .sopInstanceUID, vr: .UI)
        ds.setString("1.2.3.4.5.100", for: .studyInstanceUID, vr: .UI)
        ds.setString("1.2.3.4.5.200", for: .seriesInstanceUID, vr: .UI)
        ds.setString("CT", for: .modality, vr: .CS)
        ds.setString("MONOCHROME2", for: .photometricInterpretation, vr: .CS)
        ds.setUInt16(UInt16(rows), for: .rows)
        ds.setUInt16(UInt16(columns), for: .columns)
        ds.setUInt16(16, for: .bitsAllocated)
        ds.setUInt16(16, for: .bitsStored)
        ds.setUInt16(15, for: .highBit)
        ds.setUInt16(0, for: .pixelRepresentation)
        ds.setUInt16(1, for: .samplesPerPixel)
        ds.setString("\(frames)", for: .numberOfFrames, vr: .IS)
        var px = Data()
        for f in 0..<frames {
            let v = UInt16(f + 1)
            for _ in 0..<(rows * columns) {
                px.append(UInt8(v & 0xFF)); px.append(UInt8(v >> 8))
            }
        }
        ds[.pixelData] = DataElement.data(tag: .pixelData, vr: .OW, data: px)
        return DICOMFile.create(
            dataSet: ds,
            sopClassUID: "1.2.840.10008.5.1.4.1.1.2",
            transferSyntaxUID: TransferSyntax.explicitVRLittleEndian.uid
        )
    }

    private func readU16(_ d: Data, _ index: Int) -> Int {
        let o = d.startIndex + index * 2
        return Int(d[o]) | (Int(d[o + 1]) << 8)
    }

    /// Inverting an RLE-compressed source must decode it, invert the native pixels, and
    /// write uncompressed Explicit VR Little Endian — not invert the compressed bytes and
    /// re-tag the file as RLE (which yields an undisplayable image).
    func testInvertOnRLECompressedSourceDecodesAndWritesUncompressed() throws {
        let original = makeUncompressed()
        let originalPixels = try original.tryPixelData().data

        // Encode to RLE Lossless (encapsulated) via the shared converter.
        let rleBytes = try DICOMConverter.convertToDICOM(
            dicomFile: original, to: .rleLossless, stripPrivate: false).data
        let rleFile = try DICOMFile.read(from: rleBytes)
        XCTAssertEqual(rleFile.transferSyntaxUID, TransferSyntax.rleLossless.uid,
                       "test setup: source should be RLE-encapsulated")

        // Invert through the shared editor.
        let (outBytes, info) = try PixelEditor(verbose: false)
            .processData(rleBytes, operations: [.invert])

        // Output must be uncompressed Explicit VR LE and re-readable.
        let out = try DICOMFile.read(from: outBytes)
        XCTAssertEqual(out.transferSyntaxUID, TransferSyntax.explicitVRLittleEndian.uid,
                       "a compressed source must be re-emitted uncompressed so viewers can display it")
        XCTAssertFalse(TransferSyntax.from(uid: out.transferSyntaxUID ?? "")?.isEncapsulated ?? true,
                       "output transfer syntax must not be encapsulated")

        // Pixel data must be native (directly decodable) and correctly inverted.
        let outPixels = try out.tryPixelData().data
        XCTAssertEqual(outPixels.count, originalPixels.count)
        XCTAssertEqual(info.rows, 8)
        XCTAssertEqual(info.columns, 8)

        // bitsStored 16 → maxVal 65535; inverted = 65535 - original (lossless round-trip).
        for i in 0..<(8 * 8) {
            XCTAssertEqual(readU16(outPixels, i), 65535 - readU16(originalPixels, i),
                           "pixel \(i) should be inverted")
        }
    }

    /// A native (uncompressed) source must be edited in place and keep its transfer syntax,
    /// VR, and dimensions — the decode path must not perturb the existing behavior.
    func testInvertOnNativeSourceKeepsUncompressedSyntax() throws {
        let original = makeUncompressed()
        let nativeBytes = try original.write()

        let (outBytes, _) = try PixelEditor(verbose: false)
            .processData(nativeBytes, operations: [.invert])
        let out = try DICOMFile.read(from: outBytes)

        XCTAssertEqual(out.transferSyntaxUID, TransferSyntax.explicitVRLittleEndian.uid)
        XCTAssertEqual(out.dataSet[.pixelData]?.vr, .OW, "16-bit native pixel data stays OW")

        let originalPixels = try original.tryPixelData().data
        let outPixels = try out.tryPixelData().data
        XCTAssertEqual(readU16(outPixels, 0), 65535 - readU16(originalPixels, 0))
    }

    /// Invert must touch every frame of a multi-frame image, not just frame 0.
    func testInvertAppliesToAllFrames() throws {
        let bytes = try makeMultiFrame(rows: 4, columns: 4, frames: 3).write()
        let (outBytes, info) = try PixelEditor(verbose: false)
            .processData(bytes, operations: [.invert])
        XCTAssertEqual(info.rows, 4)
        XCTAssertEqual(info.columns, 4)

        let px = try DICOMFile.read(from: outBytes).tryPixelData().data
        let frameSamples = 4 * 4
        for f in 0..<3 {
            // Frame f held the constant (f + 1); inverted = 65535 - (f + 1).
            XCTAssertEqual(readU16(px, f * frameSamples), 65535 - (f + 1),
                           "frame \(f) should be inverted")
        }
    }

    /// Crop must crop every frame and preserve the frame count.
    func testCropAppliesToAllFrames() throws {
        let bytes = try makeMultiFrame(rows: 4, columns: 4, frames: 3).write()
        let (outBytes, info) = try PixelEditor(verbose: false)
            .processData(bytes, operations: [.crop(x: 0, y: 0, width: 2, height: 2)])
        XCTAssertEqual(info.rows, 2)
        XCTAssertEqual(info.columns, 2)

        let out = try DICOMFile.read(from: outBytes)
        XCTAssertEqual(out.imageColumns, 2)
        XCTAssertEqual(out.imageRows, 2)
        XCTAssertEqual(out.numberOfFrames, 3, "crop must preserve the frame count")

        let px = try out.tryPixelData().data
        XCTAssertEqual(px.count, 3 * 2 * 2 * 2, "3 frames × 2×2 × 2 bytes/sample")
        let frameSamples = 2 * 2
        for f in 0..<3 {
            XCTAssertEqual(readU16(px, f * frameSamples), f + 1,
                           "cropped frame \(f) keeps its value")
        }
    }

    // MARK: - Invert must keep the VOI window consistent (the "all-white" regression)

    /// Builds an 8×8 16-bit MONOCHROME2 image with a diagonal gradient and an explicit
    /// stored VOI window. `bitsStored`/`signed`/rescale are configurable so the same
    /// helper covers the unsigned-doesn't-fill-the-range, rescaled-CT, and signed cases.
    private func makeWindowed(
        bitsStored: Int = 16,
        signed: Bool = false,
        photometric: String = "MONOCHROME2",
        windowCenter: String? = "1500",
        windowWidth: String? = "3000",
        rescaleIntercept: String? = nil,
        rescaleSlope: String? = nil,
        valueAt: (_ index: Int) -> Int = { $0 * 47 }   // 0…2961 across 64 pixels
    ) -> DICOMFile {
        let rows = 8, columns = 8
        var ds = DataSet()
        ds.setString("1.2.840.10008.5.1.4.1.1.2", for: .sopClassUID, vr: .UI)
        ds.setString("1.2.3.4.5.6.7.8.20", for: .sopInstanceUID, vr: .UI)
        ds.setString("1.2.3.4.5.100", for: .studyInstanceUID, vr: .UI)
        ds.setString("1.2.3.4.5.200", for: .seriesInstanceUID, vr: .UI)
        ds.setString("CT", for: .modality, vr: .CS)
        ds.setString(photometric, for: .photometricInterpretation, vr: .CS)
        ds.setUInt16(UInt16(rows), for: .rows)
        ds.setUInt16(UInt16(columns), for: .columns)
        ds.setUInt16(16, for: .bitsAllocated)
        ds.setUInt16(UInt16(bitsStored), for: .bitsStored)
        ds.setUInt16(UInt16(bitsStored - 1), for: .highBit)
        ds.setUInt16(signed ? 1 : 0, for: .pixelRepresentation)
        ds.setUInt16(1, for: .samplesPerPixel)
        if let c = windowCenter { ds.setString(c, for: .windowCenter, vr: .DS) }
        if let w = windowWidth { ds.setString(w, for: .windowWidth, vr: .DS) }
        if let i = rescaleIntercept { ds.setString(i, for: .rescaleIntercept, vr: .DS) }
        if let s = rescaleSlope { ds.setString(s, for: .rescaleSlope, vr: .DS) }
        var px = Data()
        for i in 0..<(rows * columns) {
            let v = UInt16(bitPattern: Int16(truncatingIfNeeded: valueAt(i)))
            px.append(UInt8(v & 0xFF)); px.append(UInt8(v >> 8))
        }
        ds[.pixelData] = DataElement.data(tag: .pixelData, vr: .OW, data: px)
        return DICOMFile.create(
            dataSet: ds,
            sopClassUID: "1.2.840.10008.5.1.4.1.1.2",
            transferSyntaxUID: TransferSyntax.explicitVRLittleEndian.uid
        )
    }

    /// An unsigned 16-bit image whose data occupies only the low part of the range is the
    /// classic "invert → solid white" case: without a window fix, every inverted pixel lands
    /// near 65535, far above the stored Window Center, so the viewer clamps it to white.
    /// After the fix the Window Center is inverted too, so the result displays as a negative.
    func testInvertInvertsVOIWindowCenter() throws {
        // center 1500, width 3000, no rescale → pivot = 65535, k = 65535.
        let bytes = try makeWindowed(windowCenter: "1500", windowWidth: "3000").write()
        let (outBytes, _) = try PixelEditor(verbose: false).processData(bytes, operations: [.invert])
        let out = try DICOMFile.read(from: outBytes)

        let win = try XCTUnwrap(out.windowSettings(), "inverted file must still carry a VOI window")
        XCTAssertEqual(win.center, 65535.0 - 1500.0, accuracy: 0.5,
                       "Window Center must invert around the stored max (65535 − 1500)")
        XCTAssertEqual(win.width, 3000.0, accuracy: 0.5, "Window Width is a span and must not change")
    }

    /// With a non-trivial Rescale Intercept the Window Center (in output/HU units) must
    /// transform as `slope·pivot + 2·intercept − center`, which is equivalent to inverting
    /// the *stored* center around the pivot. This is the case that matters for real CT.
    func testInvertInvertsWindowCenterWithRescaleIntercept() throws {
        // bitsStored 12 → pivot 4095; slope 1, intercept −1024; center 40 HU, width 400.
        let bytes = try makeWindowed(
            bitsStored: 12, windowCenter: "40", windowWidth: "400",
            rescaleIntercept: "-1024", rescaleSlope: "1",
            valueAt: { min(4095, $0 * 47) }
        ).write()
        let (outBytes, _) = try PixelEditor(verbose: false).processData(bytes, operations: [.invert])
        let out = try DICOMFile.read(from: outBytes)

        // slope·pivot + 2·intercept − center = 1·4095 + 2·(−1024) − 40 = 2007.
        let win = try XCTUnwrap(out.windowSettings())
        XCTAssertEqual(win.center, 2007.0, accuracy: 0.5)
        XCTAssertEqual(win.width, 400.0, accuracy: 0.5)
    }

    /// Multiple Window Center values (DICOM VM 1-n) must each be inverted.
    func testInvertInvertsAllWindowCenters() throws {
        var ds = try makeWindowed(windowCenter: "1500", windowWidth: "3000").dataSet
        ds.setStrings(["1500", "500"], for: .windowCenter, vr: .DS)
        ds.setStrings(["3000", "1000"], for: .windowWidth, vr: .DS)
        let bytes = try DICOMFile.create(
            dataSet: ds, sopClassUID: "1.2.840.10008.5.1.4.1.1.2",
            transferSyntaxUID: TransferSyntax.explicitVRLittleEndian.uid).write()

        let (outBytes, _) = try PixelEditor(verbose: false).processData(bytes, operations: [.invert])
        let centers = try XCTUnwrap(DICOMFile.read(from: outBytes).dataSet.decimalStrings(for: .windowCenter))
            .map { $0.value }
        XCTAssertEqual(centers.count, 2)
        XCTAssertEqual(centers[0], 65535.0 - 1500.0, accuracy: 0.5)
        XCTAssertEqual(centers[1], 65535.0 - 500.0, accuracy: 0.5)
    }

    /// Signed pixel data must invert around −1 (min+max of a two's-complement range), NOT
    /// the unsigned `maxValue`. The old code used `maxValue` (65535) as the pivot, which drove
    /// every signed sample past the +32767 clamp → a solid-white frame.
    func testInvertSignedDoesNotClampToWhite() throws {
        // signed 16-bit, values −1000…+1000; no window → auto-window path.
        let original = makeWindowed(
            signed: true, windowCenter: nil, windowWidth: nil,
            valueAt: { ($0 - 32) * 30 })   // −960 … +930
        let originalPixels = try original.tryPixelData().data
        let (outBytes, _) = try PixelEditor(verbose: false)
            .processData(try original.write(), operations: [.invert])
        let outPixels = try DICOMFile.read(from: outBytes).tryPixelData().data

        for i in 0..<64 {
            let o = Int(Int16(bitPattern: UInt16(readU16(originalPixels, i))))
            let n = Int(Int16(bitPattern: UInt16(readU16(outPixels, i))))
            XCTAssertEqual(n, -1 - o, "signed pixel \(i) must invert around −1, staying in range")
        }
    }

    /// Baking a window/level must reset the stored VOI window to the full output range so the
    /// baked contrast is what a viewer shows (rather than re-clipping with the pre-bake window).
    func testWindowLevelBakeResetsVOIWindow() throws {
        let bytes = try makeWindowed(bitsStored: 12, windowCenter: "40", windowWidth: "400",
                                     rescaleIntercept: "-1024", rescaleSlope: "1",
                                     valueAt: { min(4095, $0 * 47) }).write()
        let (outBytes, _) = try PixelEditor(verbose: false)
            .processData(bytes, operations: [.windowLevel(center: 500, width: 800)])
        let win = try XCTUnwrap(try DICOMFile.read(from: outBytes).windowSettings())
        // Full range for bitsStored 12 (PS3.3 C.11.2.1.2.1, D66): stored center 2048 → HU 1024; width 4096.
        XCTAssertEqual(win.center, 1024, accuracy: 1e-9)
        XCTAssertEqual(win.width, 4096.0, accuracy: 1e-9)
    }

    /// Baking on SIGNED data must use the signed stored range [−2^(b−1), 2^(b−1)−1], not the
    /// unsigned [0, 2^b−1]. Otherwise the reset window is twice the range the baked (signed-
    /// clamped) pixels actually occupy and the image renders ~2× too dark.
    func testWindowLevelBakeUsesSignedRange() throws {
        // signed 16-bit, no rescale. Stored range [−32768, 32767] → the full-range window of
        // PS3.3 C.11.2.1.2.1, center (x1+x2+1)/2 = 0, width x2−x1+1 = 65536 (D66).
        // Inputs −1280…+1240 straddle the [−1000,+1000] window, so the extremes bake to the
        // signed range extremes (below window → −32768, above window → +32767).
        let bytes = try makeWindowed(signed: true, windowCenter: "0", windowWidth: "2000",
                                     valueAt: { ($0 - 32) * 40 }).write()
        let (outBytes, _) = try PixelEditor(verbose: false)
            .processData(bytes, operations: [.windowLevel(center: 0, width: 2000)])
        let out = try DICOMFile.read(from: outBytes)
        let win = try XCTUnwrap(out.windowSettings())
        XCTAssertEqual(win.center, 0, accuracy: 1e-9, "signed full-range center is (−32768+32767+1)/2")
        XCTAssertEqual(win.width, 65536.0, accuracy: 1e-9, "signed full-range width is 32767−(−32768)+1")

        // Pixels outside the window must bake to the signed range extremes, not clamp from 65535.
        let px = try out.tryPixelData().data
        let stored = (0..<64).map { Int(Int16(bitPattern: UInt16(readU16(px, $0)))) }
        XCTAssertEqual(stored.max() ?? 0, 32767, "brightest baked signed pixel must reach the signed max")
        XCTAssertEqual(stored.min() ?? 0, -32768, "darkest baked signed pixel must reach the signed min")
    }

#if canImport(CoreGraphics)
    /// End-to-end viewer check: render the inverted frame through the SAME shared window
    /// policy the DICOMStudio viewer and image exporter use (`renderFrameForExport`, which
    /// honours the file's stored window). Before the fix the inverted frame rendered solid
    /// white (mean ≈ 255); after it, it is the photographic negative of the original —
    /// darkest↔brightest swapped and mean ≈ 255 − originalMean, nowhere near saturation.
    func testInvertRendersAsNegativeNotWhiteThroughViewerPolicy() throws {
        let original = makeWindowed(windowCenter: "1500", windowWidth: "3000")
        let originalMean = try meanGray(of: original)

        let (outBytes, _) = try PixelEditor(verbose: false)
            .processData(try original.write(), operations: [.invert])
        let inverted = try DICOMFile.read(from: outBytes)
        let invertedMean = try meanGray(of: inverted)

        XCTAssertLessThan(invertedMean, 250.0,
                          "inverted frame must NOT render as solid white (regression: mean was ≈255)")
        XCTAssertEqual(invertedMean, 255.0 - originalMean, accuracy: 6.0,
                       "inverted frame must be the photographic negative of the original")
    }

    /// The negative must also hold for MONOCHROME1 (the renderer already flips MONOCHROME1
    /// display polarity). Inverting pixels AND the window keeps the two flips consistent, so
    /// the rendered result is a true PER-PIXEL negative — not an unchanged image. A mean
    /// comparison is insufficient here: this frame is balanced around mid-gray, so its mean
    /// is nearly invariant under negation; only a per-pixel check distinguishes negate vs no-op.
    func testInvertRendersAsNegativeForMonochrome1() throws {
        let original = makeWindowed(photometric: "MONOCHROME1", windowCenter: "1500", windowWidth: "3000")
        let before = try renderGray(of: original)

        let (outBytes, _) = try PixelEditor(verbose: false)
            .processData(try original.write(), operations: [.invert])
        let after = try renderGray(of: try DICOMFile.read(from: outBytes))

        XCTAssertEqual(before.count, after.count)
        var maxComplementError = 0, changed = 0
        for i in 0..<before.count {
            maxComplementError = max(maxComplementError, abs((255 - Int(before[i])) - Int(after[i])))
            if before[i] != after[i] { changed += 1 }
        }
        XCTAssertLessThanOrEqual(maxComplementError, 2,
            "every MONOCHROME1 pixel must render as its complement (true negative)")
        XCTAssertGreaterThan(changed, before.count / 2,
            "MONOCHROME1 invert must visibly change most pixels, not be a no-op")
    }

    /// Renders frame 0 through the shared export/viewer window policy and returns the 8-bit
    /// gray levels (0 = black … 255 = white).
    private func renderGray(of file: DICOMFile) throws -> [UInt8] {
        let pd = try file.tryPixelData()
        let image = try DICOMImageExporter.renderFrameForExport(
            file: file, pixelData: pd, frameIndex: 0,
            applyWindow: false, windowCenter: nil, windowWidth: nil)
        let w = image.width, h = image.height
        var buf = [UInt8](repeating: 0, count: w * h)
        let ctx = try XCTUnwrap(CGContext(
            data: &buf, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.none.rawValue))
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        return buf
    }

    private func meanGray(of file: DICOMFile) throws -> Double {
        let buf = try renderGray(of: file)
        return Double(buf.reduce(0) { $0 + Int($1) }) / Double(buf.count)
    }
#endif
}

// MARK: - DICOM 2026a: derived image, units, geometry, ranges (D169-D174)

/// PS3.3 2026a rules the shared PixelEditor applies itself since 2026-10-01, so the
/// dicom-pixedit CLI and DICOMStudio write the same conformant output.
final class PixelEditorStandardTests: XCTestCase {

    private let ctStorage = "1.2.840.10008.5.1.4.1.1.2"   // PS3.6 Table A-1 CT Image Storage

    /// 10x8 single-sample image; `configure` adds attributes before writing.
    private func image(bitsAllocated: Int = 16, bitsStored: Int = 12, signed: Bool = false,
                       photometric: String = "MONOCHROME2", value: (Int) -> Int = { $0 * 50 },
                       configure: (inout DataSet) -> Void = { _ in }) throws -> Data {
        var ds = DataSet()
        ds.setString(ctStorage, for: .sopClassUID, vr: .UI)
        ds.setString("1.2.3.4.5", for: .sopInstanceUID, vr: .UI)
        ds.setStrings(["ORIGINAL", "PRIMARY", "AXIAL"], for: .imageType, vr: .CS)
        ds.setUInt16(1, for: .samplesPerPixel)
        ds.setString(photometric, for: .photometricInterpretation, vr: .CS)
        ds.setUInt16(8, for: .rows)
        ds.setUInt16(10, for: .columns)
        ds.setUInt16(UInt16(bitsAllocated), for: .bitsAllocated)
        ds.setUInt16(UInt16(bitsStored), for: .bitsStored)
        ds.setUInt16(UInt16(bitsStored - 1), for: .highBit)
        ds.setUInt16(signed ? 1 : 0, for: .pixelRepresentation)
        var px = Data()
        for i in 0..<80 {
            let v = UInt16(bitPattern: Int16(truncatingIfNeeded: value(i)))
            px.append(UInt8(v & 0xFF))
            if bitsAllocated == 16 { px.append(UInt8(v >> 8)) }
        }
        ds[.pixelData] = DataElement.data(tag: .pixelData, vr: bitsAllocated == 16 ? .OW : .OB, data: px)
        configure(&ds)
        var file = DICOMFile.create(dataSet: ds, sopClassUID: ctStorage, sopInstanceUID: "1.2.3.4.5",
                                    transferSyntaxUID: TransferSyntax.explicitVRLittleEndian.uid)
        var meta = file.fileMetaInformation
        meta.setString("1.2.3.999", for: .implementationClassUID, vr: .UI)
        file = DICOMFile(fileMetaInformation: meta, dataSet: file.dataSet)
        return try file.write()
    }

    private func edit(_ input: Data, _ ops: [PixelOperation],
                      derivation: PixelEditDerivation? = PixelEditDerivation()) throws -> DICOMFile {
        try DICOMFile.read(from: PixelEditor(verbose: false).processData(input, operations: ops, derivation: derivation).data)
    }

    private func samples(_ file: DICOMFile) throws -> [Int] {
        let px = try XCTUnwrap(file.dataSet[.pixelData]?.valueData)
        return stride(from: 0, to: px.count - 1, by: 2).map { Int(px[$0]) | Int(px[$0 + 1]) << 8 }
    }

    /// D169: C.7.6.1.1.2 (DERIVED, new SOP Instance UID), Table C.12-10 (Derivation
    /// Description, Source Image Sequence with CID 7202 DCM 121322), PS3.10 Table 7.1-1.
    func testOutputIsADerivedImage() throws {
        let out = try edit(image(configure: { ds in
            ds.setInt(0, for: .smallestImagePixelValue, vr: .US)
            ds.setInt(3950, for: .largestImagePixelValue, vr: .US)
        }), [.invert])
        let ds = out.dataSet
        let uid = try XCTUnwrap(ds.string(for: .sopInstanceUID))
        XCTAssertNotEqual(uid, "1.2.3.4.5")
        XCTAssertEqual(out.fileMetaInformation.string(for: .mediaStorageSOPInstanceUID), uid)
        XCTAssertEqual(out.fileMetaInformation.string(for: .implementationClassUID), DICOMFile.implementationClassUID)
        XCTAssertEqual(ds.strings(for: .imageType), ["DERIVED", "PRIMARY", "AXIAL"])
        XCTAssertEqual(ds.string(for: .derivationDescription), "Pixel edit: pixel values inverted")
        let item = try XCTUnwrap(ds.sequence(for: .sourceImageSequence)?.first)
        XCTAssertEqual(item[.referencedSOPClassUID]?.stringValue, ctStorage)
        XCTAssertEqual(item[.referencedSOPInstanceUID]?.stringValue, "1.2.3.4.5")
        let purpose = try XCTUnwrap(item[.purposeOfReferenceCodeSequence]?.sequenceItems?.first)
        XCTAssertEqual(purpose[.codeValue]?.stringValue, "121322")
        XCTAssertEqual(purpose[.codingSchemeDesignator]?.stringValue, "DCM")
        XCTAssertEqual(purpose[.codeMeaning]?.stringValue, "Source image for image processing operation")
        XCTAssertNil(ds[.smallestImagePixelValue])
        XCTAssertNil(ds[.largestImagePixelValue])
        XCTAssertNil(ds[.derivationCodeSequence], "CID 7203 has no code for these edits")

        // nil keeps the source identity (pixel redaction for de-identification).
        let kept = try edit(image(), [.invert], derivation: nil)
        XCTAssertEqual(kept.dataSet.string(for: .sopInstanceUID), "1.2.3.4.5")
        XCTAssertNil(kept.dataSet[.sourceImageSequence])
    }

    /// D170: Window Center/Width are Modality LUT output units (C.11.2.1.2).
    func testWindowIsInModalityLUTOutputUnits() throws {
        // CT: Rescale Intercept −1024; window 40/400 HU. Stored 900 = −124 HU →
        // (−124 − 39.5)/399 + 0.5 = 0.0902 of 4095 → 369; stored 1064 = 40 HU → mid.
        let out = try edit(image(configure: { ds in
            ds.setString("-1024", for: .rescaleIntercept, vr: .DS)
            ds.setString("1", for: .rescaleSlope, vr: .DS)
        }), [.windowLevel(center: 40, width: 400)])
        let v = try samples(out)
        XCTAssertEqual(v[18], 369)
        XCTAssertEqual(v[0], 0)
        XCTAssertEqual(v[79], 4095)
        XCTAssertEqual(out.dataSet.string(for: .derivationDescription),
                       "Pixel edit: window center 40 width 400 baked into the stored values")
        // "Window Width (0028,1051) shall always be greater than or equal to 1".
        XCTAssertThrowsError(try edit(image(), [.windowLevel(center: 40, width: 0.5)]))
    }

    /// D171: Equation C.7.6.2.1-1 for Image Position (Patient), top level and in the
    /// Per-Frame Functional Groups; Overlay Origin (60xx,0050) is relative to the image (C.9.2).
    func testCropMovesPositionAndOverlayOrigin() throws {
        func ds(_ tag: Tag, _ values: [String]) -> DataElement {
            DataElement.strings(tag: tag, vr: .DS, values: values)
        }
        var holder = DataSet()
        holder.setSequence([SequenceItem(elements: [ds(.imagePositionPatient, ["-100", "-50", "20"])])],
                           for: .planePositionSequence)
        let planePosition = try XCTUnwrap(holder[.planePositionSequence])
        holder.setSequence([SequenceItem(elements: [ds(.imageOrientationPatient, ["1", "0", "0", "0", "1", "0"])])],
                           for: .planeOrientationSequence)
        holder.setSequence([SequenceItem(elements: [ds(.pixelSpacing, ["0.5", "0.7"])])],
                           for: .pixelMeasuresSequence)
        let shared = SequenceItem(elements: [try XCTUnwrap(holder[.planeOrientationSequence]),
                                             try XCTUnwrap(holder[.pixelMeasuresSequence])])
        let overlayOrigin = Tag(group: 0x6000, element: 0x0050)

        let out = try edit(image(configure: { d in
            d.setStrings(["-100", "-50", "20"], for: .imagePositionPatient, vr: .DS)
            d.setStrings(["1", "0", "0", "0", "1", "0"], for: .imageOrientationPatient, vr: .DS)
            d.setStrings(["0.5", "0.7"], for: .pixelSpacing, vr: .DS)
            d.setSequence([shared], for: .sharedFunctionalGroupsSequence)
            d.setSequence([SequenceItem(elements: [planePosition])], for: .perFrameFunctionalGroupsSequence)
            var origin = Data()
            for v: Int16 in [1, 1] { let u = UInt16(bitPattern: v); origin.append(UInt8(u & 0xFF)); origin.append(UInt8(u >> 8)) }
            d[overlayOrigin] = DataElement(tag: overlayOrigin, vr: .SS, length: 4, valueData: origin)
        }), [.crop(x: 2, y: 1, width: 5, height: 4)])

        // P = S + X·Δi·i + Y·Δj·j with Δi = 0.7 (column spacing), Δj = 0.5, i = 2, j = 1.
        let top = try XCTUnwrap(out.dataSet.decimalStrings(for: .imagePositionPatient)).map(\.value)
        XCTAssertEqual(top[0], -98.6, accuracy: 1e-9)
        XCTAssertEqual(top[1], -49.5, accuracy: 1e-9)
        XCTAssertEqual(top[2], 20, accuracy: 1e-9)
        let frame = try XCTUnwrap(out.dataSet.sequence(for: .perFrameFunctionalGroupsSequence)?.first)
        let plane = try XCTUnwrap(frame[.planePositionSequence]?.sequenceItems?.first)
        let fg = try XCTUnwrap(plane[.imagePositionPatient]?.decimalStringValues).map(\.value)
        XCTAssertEqual(fg[0], -98.6, accuracy: 1e-9)
        XCTAssertEqual(fg[1], -49.5, accuracy: 1e-9)
        XCTAssertEqual(out.dataSet[overlayOrigin]?.int16Values, [0, -1], "row\\column shift by (1, 2)")
    }

    /// D172: a stored sample holds Bits Stored bits (C.7.6.3.1).
    func testMaskFillIsClampedToBitsStored() throws {
        let unsigned = try samples(edit(image(), [.mask(x: 0, y: 0, width: 1, height: 1, fillValue: 9000)]))
        XCTAssertEqual(unsigned[0], 4095, "12-bit unsigned maximum, not 65535 / 9000")
        let signed = try edit(image(signed: true, value: { _ in 0 }),
                              [.mask(x: 0, y: 0, width: 1, height: 1, fillValue: -5000)])
        XCTAssertEqual(Int16(bitPattern: UInt16(try samples(signed)[0])), -2048)
    }

    /// D173: decoding a lossy source keeps Lossy Image Compression "01" (C.7.6.1.1.5).
    func testDecodingALossySourceRecordsLossyCompression() throws {
        let source = try DICOMFile.read(from: image(bitsAllocated: 8, bitsStored: 8, value: { $0 * 3 }))
        let jpeg = try DICOMConverter.convertToDICOM(dicomFile: source, to: .jpegBaseline, stripPrivate: false).data
        var file = try DICOMFile.read(from: jpeg)
        var ds = file.dataSet
        for tag in [Tag.lossyImageCompression, .lossyImageCompressionRatio, .lossyImageCompressionMethod] {
            ds.remove(tag: tag)
        }
        file = DICOMFile(fileMetaInformation: file.fileMetaInformation, dataSet: ds)
        let out = try edit(file.write(), [.invert])
        XCTAssertEqual(out.transferSyntaxUID, TransferSyntax.explicitVRLittleEndian.uid)
        XCTAssertEqual(out.dataSet.string(for: .lossyImageCompression), "01")
        XCTAssertEqual(out.dataSet.string(for: .lossyImageCompressionMethod), "ISO_10918_1")

        // A lossless source stays as it was.
        let rle = try DICOMConverter.convertToDICOM(dicomFile: source, to: .rleLossless, stripPrivate: false).data
        XCTAssertNil(try edit(rle, [.invert]).dataSet[.lossyImageCompression])
    }

    /// D174: PALETTE COLOR values are indices (C.7.6.3.1.5); Pixel Padding Value follows
    /// the remapped values or is removed on a collision (C.7.5.1.1.2).
    func testPaletteColorAndPixelPadding() throws {
        let palette = try image(bitsAllocated: 8, bitsStored: 8, photometric: "PALETTE COLOR", value: { $0 })
        for op in [PixelOperation.invert, .windowLevel(center: 128, width: 256)] {
            XCTAssertThrowsError(try edit(palette, [op])) { error in
                guard case .notApplicableToPaletteColor = error as? PixelEditError else {
                    return XCTFail("\(error)")
                }
            }
        }
        XCTAssertNoThrow(try edit(palette, [.crop(x: 0, y: 0, width: 2, height: 2)]))

        // Invert: padding 0...10 of a 12-bit image becomes 4085...4095 (MONOCHROME2:
        // Pixel Padding Value is the low end, Range Limit the high end).
        let padded = try image(value: { $0 < 4 ? 5 : 100 + $0 }, configure: { ds in
            ds[.pixelPaddingValue] = DataElement.uint16(tag: .pixelPaddingValue, value: 0)
            ds[.pixelPaddingRangeLimit] = DataElement.uint16(tag: .pixelPaddingRangeLimit, value: 10)
        })
        let inverted = try edit(padded, [.invert]).dataSet
        XCTAssertEqual(inverted.uint16(for: .pixelPaddingValue), 4085)
        XCTAssertEqual(inverted.uint16(for: .pixelPaddingRangeLimit), 4095)

        // Window 1000/100 sends padding (5) and image values below 950 to 0: padding is no
        // longer distinguishable, so both attributes are removed.
        let windowed = try edit(padded, [.windowLevel(center: 1000, width: 100)]).dataSet
        XCTAssertNil(windowed[.pixelPaddingValue])
        XCTAssertNil(windowed[.pixelPaddingRangeLimit])

        // Window 50/100 keeps padding apart (image values 104+ go to 4095): kept and
        // remapped, 0 → 0 and 10 → (10 − 49.5)/99 + 0.5 = 0.101 of 4095 → 413.
        let apart = try edit(padded, [.windowLevel(center: 50, width: 100)]).dataSet
        XCTAssertEqual(apart.uint16(for: .pixelPaddingValue), 0)
        XCTAssertEqual(apart.uint16(for: .pixelPaddingRangeLimit), 413)
    }
}
