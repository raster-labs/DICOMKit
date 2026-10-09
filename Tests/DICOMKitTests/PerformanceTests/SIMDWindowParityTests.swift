import XCTest
import DICOMCore
@testable import DICOMKit

#if canImport(Accelerate)

/// Pins `SIMDImageProcessor.applyWindowLevel` to the PS3.3 C.11.2.1.2.1 LINEAR
/// pseudo-code and to byte-identity with the scalar path (`WindowSettings.apply`
/// as tabulated by `WindowLUT`, the table `PixelDataRenderer` indexes).
final class SIMDWindowParityTests: XCTestCase {

    /// Every 16-bit unsigned stored value, as the renderer would assemble it.
    private let allValues: [UInt16] = (0..<65_536).map { UInt16($0) }

    /// 16-bit unsigned MONOCHROME2: no shift, no mask, no sign extension, no
    /// inversion — the table is exactly `UInt8(max(0, min(255, apply(x) * 255)))`.
    private let descriptor = PixelDataDescriptor(
        rows: 1, columns: 1, numberOfFrames: 1,
        bitsAllocated: 16, bitsStored: 16, highBit: 15, isSigned: false,
        samplesPerPixel: 1, photometricInterpretation: .monochrome2
    )

    private func assertParity(_ window: WindowSettings, file: StaticString = #filePath, line: UInt = #line) {
        let scalar = WindowLUT.makeGrayscale(descriptor: descriptor, window: window).table
        let simd = SIMDImageProcessor.applyWindowLevel(to: allValues, window: window)
        XCTAssertEqual(simd.count, scalar.count, file: file, line: line)
        if simd != scalar {
            let firstMismatch = zip(simd, scalar).enumerated().first { $0.element.0 != $0.element.1 }!
            XCTFail("SIMD and scalar differ (\(window.function.rawValue) c=\(window.center) w=\(window.width)) "
                    + "first at x=\(firstMismatch.offset): simd=\(firstMismatch.element.0) scalar=\(firstMismatch.element.1)",
                    file: file, line: line)
        }
    }

    // MARK: - C.11.2.1.2.1 worked example: c=2048, w=4096 over 0…255

    func test_linear_standardExample_c2048_w4096() {
        // "if (x <= 0) then y = 0; else if (x > 4095) then y = 255;
        //  else y = ((x - 2047.5) / 4095 + 0.5) * (255-0) + 0"
        let out = SIMDImageProcessor.applyWindowLevel(to: [0, 1, 2048, 4095, 4096, 65_535],
                                                      windowCenter: 2048, windowWidth: 4096)
        XCTAssertEqual(out[0], 0)
        XCTAssertEqual(out[1], UInt8(((1.0 - 2047.5) / 4095 + 0.5) * 255))
        XCTAssertEqual(out[2], UInt8(((2048.0 - 2047.5) / 4095 + 0.5) * 255)) // 127
        XCTAssertEqual(out[3], 255)
        XCTAssertEqual(out[4], 255)
        XCTAssertEqual(out[5], 255)
    }

    func test_linear_usesCenterMinusHalf_andWidthMinusOne_notTheOldApproximation() {
        // c=50, w=50: the standard maps x=25 to ((25-49.5)/49+0.5)*255 = 0 exactly
        // and x=74 to 255 exactly; the old (c - w/2, w) approximation put x=25 at
        // 0 and x=74 at 249.9 — a different byte.
        let out = SIMDImageProcessor.applyWindowLevel(to: [25, 26, 49, 50, 74, 75],
                                                      windowCenter: 50, windowWidth: 50)
        XCTAssertEqual(out[0], 0)
        XCTAssertEqual(out[1], UInt8(((26.0 - 49.5) / 49 + 0.5) * 255)) // 2
        XCTAssertEqual(out[2], UInt8(((49.0 - 49.5) / 49 + 0.5) * 255)) // 124
        XCTAssertEqual(out[3], UInt8(((50.0 - 49.5) / 49 + 0.5) * 255)) // 130
        XCTAssertEqual(out[4], 255)
        XCTAssertEqual(out[5], 255)
    }

    func test_linear_widthOne_isThreshold_c2048() {
        // "c=2048, w=1 becomes: if (x <= 2047.5) then y = 0 else if (x > 2047.5) then y = 255"
        let out = SIMDImageProcessor.applyWindowLevel(to: [0, 2047, 2048, 65_535],
                                                      windowCenter: 2048, windowWidth: 1)
        XCTAssertEqual(out, [0, 0, 255, 255])
    }

    func test_linear_widthBelowOne_isClampedToOne_likeWindowSettings() {
        // WindowSettings clamps width to >= 1 ("shall always be greater than or
        // equal to 1"); the SIMD path must behave the same, not return zeros.
        let out = SIMDImageProcessor.applyWindowLevel(to: [0, 50, 100, 150, 200],
                                                      windowCenter: 100, windowWidth: 0)
        XCTAssertEqual(out, [0, 0, 255, 255, 255])
    }

    // MARK: - Parity with the scalar path over the whole 16-bit domain

    func test_parity_linear_typicalWindows() {
        assertParity(WindowSettings(center: 2048, width: 4096))
        assertParity(WindowSettings(center: 1064, width: 400))
        assertParity(WindowSettings(center: 40, width: 80))
        assertParity(WindowSettings(center: 32_768, width: 65_536))
        assertParity(WindowSettings(center: 60_000, width: 10))
    }

    func test_parity_linear_fractionalCenterAndWidth() {
        // "Fractional values of Window Center and Window Width are permitted"
        assertParity(WindowSettings(center: 1234.56, width: 789.01))
        assertParity(WindowSettings(center: 0.5, width: 3.3))
        assertParity(WindowSettings(center: 40_000.25, width: 1.5))
    }

    func test_parity_linear_thresholdWidthOne() {
        assertParity(WindowSettings(center: 2048, width: 1))
        assertParity(WindowSettings(center: 2047.5, width: 1))
        assertParity(WindowSettings(center: 0, width: 1))
        assertParity(WindowSettings(center: 65_535, width: 1))
    }

    func test_parity_linearExact() {
        assertParity(WindowSettings(center: 2048, width: 4096, function: .linearExact))
        assertParity(WindowSettings(center: 1064, width: 400, function: .linearExact))
        assertParity(WindowSettings(center: 100.5, width: 1, function: .linearExact))
    }

    func test_parity_sigmoid() {
        assertParity(WindowSettings(center: 2048, width: 4096, function: .sigmoid))
        assertParity(WindowSettings(center: 1064, width: 400, function: .sigmoid))
        assertParity(WindowSettings(center: 30_000, width: 2, function: .sigmoid))
    }

    func test_parity_matchesRendererTable_viaCachedLUT() {
        // The cached table PixelDataRenderer actually indexes, not just the
        // freshly built one.
        let window = WindowSettings(center: 500, width: 1000)
        let cached = WindowLUT.grayscale(descriptor: descriptor, window: window).table
        XCTAssertEqual(SIMDImageProcessor.applyWindowLevel(to: allValues, window: window), cached)
    }
}

#endif
