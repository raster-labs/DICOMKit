import XCTest
@testable import DICOMRenderKit
import DICOMCore
import DICOMKit

#if canImport(CoreGraphics)
import CoreGraphics
#endif

/// Pins what both backends render against the DICOM 2026a text, rather than
/// against each other (`MetalCPUEquivalenceTests` does that).
///
/// See DICOMRENDERKIT_STANDARD_IMPLEMENTATION.md for the clauses and for the
/// findings that live in DICOMCore / DICOMKit (D63–D67).
final class RenderStandardConformanceTests: XCTestCase {

    #if canImport(Metal) && canImport(CoreGraphics)

    private func requireMetal() throws -> MetalFrameRenderer {
        guard let renderer = MetalFrameRenderer(minimumPixelCount: 0) else {
            throw XCTSkip("No Metal device on this machine")
        }
        return renderer
    }

    private func bytes(of image: CGImage) throws -> [UInt8] {
        [UInt8](try XCTUnwrap(image.dataProvider?.data as Data?))
    }

    /// Every backend that renders the request, labelled.
    private func backends() throws -> [(String, FrameRenderBackend)] {
        var out: [(String, FrameRenderBackend)] = [("cpu", CPUFrameRenderer())]
        if let metal = MetalFrameRenderer(minimumPixelCount: 0) { out.append(("metal", metal)) }
        return out
    }

    private func signed16(_ values: [Int16]) -> Data {
        var data = Data()
        for v in values {
            let u = UInt16(bitPattern: v)
            data.append(UInt8(u & 0xFF))
            data.append(UInt8(u >> 8))
        }
        return data
    }

    // MARK: - PS3.5 8.1.1: a Pixel Cell is Bits Allocated wide

    /// The kernels assemble one or two bytes per sample. A 32-bit cell read as its
    /// low two bytes is another value (65,541 would render as 5), so the GPU must
    /// decline it and leave the frame to the CPU.
    func testMetalDeclinesPixelCellsWiderThanTwoBytes() throws {
        let metal = try requireMetal()
        var cells = Data()
        for value: UInt32 in [5, 65_541, 70_000, 1_000_000] {
            withUnsafeBytes(of: value.littleEndian) { cells.append(contentsOf: $0) }
        }
        let monochrome = PixelData(data: cells, descriptor: PixelDataDescriptor(
            rows: 2, columns: 2, bitsAllocated: 32, bitsStored: 32, highBit: 31,
            isSigned: false, photometricInterpretation: .monochrome2))
        let request = FrameRenderRequest(
            pixelData: monochrome, window: WindowSettings(center: 500_000, width: 1_000_000))
        XCTAssertNil(metal.renderFrame(request))
        XCTAssertNil(metal.renderDisplayTexture(request))

        let rgb = PixelData(data: Data(count: 2 * 2 * 3 * 4), descriptor: PixelDataDescriptor(
            rows: 2, columns: 2, bitsAllocated: 32, bitsStored: 32, highBit: 31,
            isSigned: false, samplesPerPixel: 3, photometricInterpretation: .rgb))
        XCTAssertNil(metal.renderFrame(FrameRenderRequest(pixelData: rgb)))
    }

    // MARK: - PS3.3 C.11.2.1.2.1: the LINEAR window

    /// The worked example of C.11.2.1.2.1 for c = 0, w = 100 on an output range
    /// 0–255: x ≤ −50 → 0, x > 49 → 255, otherwise ((x + 0.5) / 99 + 0.5) × 255.
    /// Signed 16-bit input (Pixel Representation 1, sign bit = High Bit).
    func testLinearWindowMatchesTheWorkedExampleOnEveryBackend() throws {
        let inputs: [Int16] = [-1000, -51, -50, -49, 0, 48, 49, 50, 1000]
        let pixelData = PixelData(data: signed16(inputs), descriptor: PixelDataDescriptor(
            rows: 1, columns: inputs.count, bitsAllocated: 16, bitsStored: 16, highBit: 15,
            isSigned: true, photometricInterpretation: .monochrome2))
        let request = FrameRenderRequest(
            pixelData: pixelData, window: WindowSettings(center: 0, width: 100))
        let expected: [UInt8] = inputs.map { x in
            let x = Double(x)
            if x <= -50 { return 0 }
            if x > 49 { return 255 }
            return UInt8(((x + 0.5) / 99 + 0.5) * 255)
        }
        for (name, backend) in try backends() {
            let image = try XCTUnwrap(backend.renderFrame(request), name)
            XCTAssertEqual(try bytes(of: image), expected, name)
        }
    }

    // MARK: - PS3.3 C.7.6.3.1.2: MONOCHROME1 after the VOI transformation

    /// "The minimum sample value is intended to be displayed as white after any
    /// VOI gray scale transformations have been performed": the window selects
    /// first, then the output is inverted. Below the window is white, above it
    /// black, and the ramp runs downwards.
    func testMonochrome1InvertsAfterTheWindowOnEveryBackend() throws {
        let inputs: [Int16] = [-1000, -50, 0, 49, 50, 1000]
        let pixelData = PixelData(data: signed16(inputs), descriptor: PixelDataDescriptor(
            rows: 1, columns: inputs.count, bitsAllocated: 16, bitsStored: 16, highBit: 15,
            isSigned: true, photometricInterpretation: .monochrome1))
        let request = FrameRenderRequest(
            pixelData: pixelData, window: WindowSettings(center: 0, width: 100))
        for (name, backend) in try backends() {
            let out = try bytes(of: try XCTUnwrap(backend.renderFrame(request), name))
            XCTAssertEqual(out.first, 255, "\(name): below the window is white")
            XCTAssertEqual(out.last, 0, "\(name): above the window is black")
            XCTAssertEqual(out[1], 255, "\(name): the lower edge x = c − w/2 is ymin, shown white")
            XCTAssertEqual(out[5], 0, "\(name)")
            XCTAssertGreaterThan(out[2], out[3], "\(name): the ramp runs downwards")
        }
    }

    // MARK: - PS3.3 C.7.6.3.1.3: Planar Configuration

    /// Enumerated Value 1: "R1, R2, R3, …, G1, G2, G3, …, B1, B2, B3". Two pixels,
    /// pure red then pure blue, must come out as red then blue on every backend.
    func testPlanarConfigurationOneIsReadColourByPlane() throws {
        let planes: [UInt8] = [255, 0,   0, 0,   0, 255]    // R1 R2, G1 G2, B1 B2
        let pixelData = PixelData(data: Data(planes), descriptor: PixelDataDescriptor(
            rows: 1, columns: 2, bitsAllocated: 8, bitsStored: 8, highBit: 7, isSigned: false,
            samplesPerPixel: 3, photometricInterpretation: .rgb, planarConfiguration: 1))
        for (name, backend) in try backends() {
            let out = try bytes(of: try XCTUnwrap(
                backend.renderFrame(FrameRenderRequest(pixelData: pixelData)), name))
            XCTAssertEqual(Array(out[0..<3]), [255, 0, 0], "\(name): first pixel red")
            XCTAssertEqual(Array(out[4..<7]), [0, 0, 255], "\(name): second pixel blue")
        }
    }

    // MARK: - PS3.5 8.1.1 on the CPU (D67)

    /// C.11.2.1.2.1 LINEAR with the D63 quantisation (the floor of the exact value).
    private func linearByte(_ x: Double, _ c: Double, _ w: Double) -> UInt8 {
        if x <= c - 0.5 - (w - 1) / 2 { return 0 }
        if x > c - 0.5 + (w - 1) / 2 { return 255 }
        return UInt8(((x - (c - 0.5)) / (w - 1) + 0.5) * 255 + 1e-9)
    }

    private func cells32(_ values: [UInt32]) -> Data {
        var data = Data()
        for value in values { withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) } }
        return data
    }

    /// A Bits Allocated 32 cell is four bytes: 65,541 is not 5. Rendered whole on the
    /// CPU, through the service too (the GPU declines it).
    func testWideCellsRenderWholeOnTheCPU() throws {
        let values: [UInt32] = [5, 65_541, 70_000, 1_000_000]
        let pixelData = PixelData(data: cells32(values), descriptor: PixelDataDescriptor(
            rows: 1, columns: 4, bitsAllocated: 32, bitsStored: 32, highBit: 31,
            isSigned: false, photometricInterpretation: .monochrome2))
        let request = FrameRenderRequest(
            pixelData: pixelData, window: WindowSettings(center: 500_000, width: 1_000_000))
        let expected = values.map { linearByte(Double($0), 500_000, 1_000_000) }
        XCTAssertNotEqual(expected[0], expected[1], "the fixture must tell 5 from 65,541")
        XCTAssertEqual(try bytes(of: try XCTUnwrap(CPUFrameRenderer().renderFrame(request))), expected)
        XCTAssertEqual(try bytes(of: try XCTUnwrap(FrameRenderService().renderFrame(request))), expected)
        XCTAssertEqual(try bytes(of: try XCTUnwrap(
            PixelDataRenderer(pixelData: pixelData).renderMonochromeFrame(0, window: request.window!))), expected)
    }

    /// 32-bit RGB samples scale over their 32 stored bits.
    func testWideColourCellsRenderWhole() throws {
        let pixelData = PixelData(data: cells32([0xFFFF_FFFF, 0x8000_0000, 0]), descriptor: PixelDataDescriptor(
            rows: 1, columns: 1, bitsAllocated: 32, bitsStored: 32, highBit: 31,
            isSigned: false, samplesPerPixel: 3, photometricInterpretation: .rgb))
        let out = try bytes(of: try XCTUnwrap(CPUFrameRenderer().renderFrame(FrameRenderRequest(pixelData: pixelData))))
        XCTAssertEqual(Array(out[0..<3]), [255, 127, 0])
    }

    // MARK: - PS3.4 N.2 chain (P-PIPELINE)

    private func signedFrame(_ values: [Int16], photometric: PhotometricInterpretation = .monochrome2) -> PixelData {
        PixelData(data: signed16(values), descriptor: PixelDataDescriptor(
            rows: 1, columns: values.count, bitsAllocated: 16, bitsStored: 16, highBit: 15,
            isSigned: true, photometricInterpretation: photometric))
    }

    /// Renders on every backend and demands the expected bytes from each.
    private func assertEveryBackend(_ request: FrameRenderRequest, _ expected: [UInt8],
                                    _ label: String, file: StaticString = #filePath, line: UInt = #line) throws {
        for (name, backend) in try backends() {
            let image = try XCTUnwrap(backend.renderFrame(request), "\(name) declined \(label)", file: file, line: line)
            XCTAssertEqual(try bytes(of: image), expected, "\(name): \(label)", file: file, line: line)
        }
    }

    /// C.11.2.1.2.1: the window applies to the rescaled value. Slope 2, window 0 / 100
    /// in modality units: each stored s shows as LINEAR(2s).
    func testWindowAppliesAfterARescaleSlope() throws {
        let stored: [Int16] = [-100, -26, -25, -24, 0, 24, 25, 26, 100]
        let request = FrameRenderRequest(
            pixelData: signedFrame(stored), window: WindowSettings(center: 0, width: 100),
            modalityLUT: .rescale(slope: 2, intercept: 0, type: nil))
        try assertEveryBackend(request, stored.map { linearByte(2 * Double($0), 0, 100) }, "slope 2")
    }

    /// A negative slope reverses the stored order: the highest stored value is the
    /// lowest modality value, shown darkest.
    func testNegativeSlopeIsNotInverted() throws {
        let stored: [Int16] = [-100, 0, 49, 50, 51, 100, 200]
        let request = FrameRenderRequest(
            pixelData: signedFrame(stored),
            modalityLUT: .rescale(slope: -1, intercept: 100, type: nil),
            voiLUT: .window(center: 100, width: 100, explanation: nil, function: .linear))
        let expected = stored.map { linearByte(100 - Double($0), 100, 100) }
        XCTAssertEqual(expected.first, 255)
        XCTAssertEqual(expected.last, 0)
        try assertEveryBackend(request, expected, "slope -1")
    }

    /// C.11.1.1.1 (Modality LUT clamps to its ends), C.11.2.1.1 (VOI LUT output
    /// 0…2^n−1 normalised by 2^n−1): an 8-bit VOI table whose entry is the byte shown.
    func testTableModalityAndVOILUTs() throws {
        let stored: [Int16] = [0, 10, 11, 12, 13, 50]
        let modality = LUTData(numberOfEntries: 4, firstValueMapped: 10, bitsPerEntry: 16,
                               data: [0, 1000, 2000, 3000])
        let voi = LUTData(numberOfEntries: 3001, firstValueMapped: 0, bitsPerEntry: 8,
                          data: (0...3000).map { $0 * 255 / 3000 })
        let request = FrameRenderRequest(
            pixelData: signedFrame(stored), modalityLUT: .lut(modality), voiLUT: .lut(voi))
        try assertEveryBackend(request, [0, 0, 85, 170, 255, 255], "table LUTs")
    }

    /// C.7.6.3.1.2: MONOCHROME1 is INVERSE by default; PS3.4 N.2: an explicit
    /// Presentation LUT replaces the image's polarity.
    func testMonochrome1DefaultsToInverseAndAnExplicitShapeWins() throws {
        let stored: [Int16] = [-100, 0, 100]
        let window = VOILUT.window(center: 0, width: 100, explanation: nil, function: .linear)
        let grey = stored.map { linearByte(Double($0), 0, 100) }
        // INVERSE is "maximum value − output value" on the continuous output (C.11.6.1.2),
        // quantised afterwards: floor((1 − y) · 255), not 255 − floor(y · 255).
        let inverted: [UInt8] = stored.map { x in
            let x = Double(x)
            let y = x <= -50 ? 0 : x > 49 ? 1 : (x + 0.5) / 99 + 0.5
            return UInt8((1 - y) * 255 + 1e-9)
        }
        try assertEveryBackend(
            FrameRenderRequest(pixelData: signedFrame(stored, photometric: .monochrome1), voiLUT: window),
            inverted, "MONOCHROME1 default")
        try assertEveryBackend(
            FrameRenderRequest(pixelData: signedFrame(stored, photometric: .monochrome1), voiLUT: window,
                               presentationLUT: .identity),
            grey, "explicit IDENTITY")
    }

    /// Without the chain the request behaves as before: `window` in stored units.
    func testWithoutTheChainTheWindowIsInStoredUnits() throws {
        let stored: [Int16] = [-100, 0, 100]
        let request = FrameRenderRequest(pixelData: signedFrame(stored), window: WindowSettings(center: 0, width: 100))
        XCTAssertFalse(request.usesDisplayPipeline)
        try assertEveryBackend(request, stored.map { linearByte(Double($0), 0, 100) }, "stored window")
    }

    // MARK: - PS3.3 C.11.15.1.1 (P-ICC)

    /// Colour output is tagged with the image's ICC Profile; monochrome is not.
    func testColourOutputCarriesTheICCProfile() throws {
        let p3 = try XCTUnwrap(CGColorSpace(name: CGColorSpace.displayP3)?.copyICCData() as Data?)
        let rgb = PixelData(data: Data([255, 0, 0, 0, 0, 255]), descriptor: PixelDataDescriptor(
            rows: 1, columns: 2, bitsAllocated: 8, bitsStored: 8, highBit: 7, isSigned: false,
            samplesPerPixel: 3, photometricInterpretation: .rgb))
        let request = FrameRenderRequest(pixelData: rgb, iccProfile: p3)
        for (name, backend) in try backends() {
            let image = try XCTUnwrap(backend.renderFrame(request), name)
            XCTAssertEqual(image.colorSpace?.copyICCData() as Data?, p3, "\(name): tagged with the profile")
            XCTAssertEqual(Array(try bytes(of: image)[0..<3]), [255, 0, 0], "\(name): bytes unchanged")
        }
        if let metal = MetalFrameRenderer(minimumPixelCount: 0) {
            let shown = try XCTUnwrap(metal.renderForDisplay(request))
            XCTAssertEqual(shown.texture.colorSpace?.copyICCData() as Data?, p3)
        }
        let grey = FrameRenderRequest(pixelData: signedFrame([0]), window: WindowSettings(center: 0, width: 100),
                                      iccProfile: p3)
        XCTAssertNil(grey.outputColorSpace)
        XCTAssertNil(FrameRenderRequest(pixelData: rgb, iccProfile: Data([1, 2, 3])).outputColorSpace)
    }

    /// The print preparer reads Bits Allocated 32 cells whole too (D67): 65,541 is
    /// between the frame's extremes, not the value 5 its low two bytes hold.
    func testPrintPreparerReadsWideCellsWhole() async throws {
        let pixelData = PixelData(data: cells32([5, 65_541, 1_000_000]), descriptor: PixelDataDescriptor(
            rows: 1, columns: 3, bitsAllocated: 32, bitsStored: 32, highBit: 31,
            isSigned: false, photometricInterpretation: .monochrome2))
        let prepared = try await ImagePreprocessor().prepareForPrint(
            pixelData: pixelData, dataSet: DataSet(), frameIndex: 0,
            colorMode: .grayscale, outputBitDepth: 8)
        let out = [UInt8](prepared.pixelData)
        XCTAssertEqual(out.first, 0)
        XCTAssertEqual(out.last, 255)
        XCTAssertTrue((1..<64).contains(out[1]), "65,541 sits about 6.5 % up the range, got \(out[1])")
    }

    #endif
}
