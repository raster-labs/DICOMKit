import Testing
import Foundation
@testable import DICOMCore

/// D63: the display byte is the floor of the exact VOI output (PS3.3 2026a C.11.2.1.2.1).
@Suite("Window quantisation")
struct WindowQuantisationTests {

    private func descriptor(bits: Int, photometric: PhotometricInterpretation = .monochrome2) -> PixelDataDescriptor {
        PixelDataDescriptor(rows: 1, columns: 1, bitsAllocated: bits <= 8 ? 8 : 16,
                            bitsStored: bits, highBit: bits - 1, isSigned: false,
                            photometricInterpretation: photometric)
    }

    /// "A Window Center of 2^(n-1) and a Window Width of 2^n … represents a mathematical
    /// identity": for n = 8 each stored value is its own display byte.
    @Test("8-bit identity window is the identity")
    func eightBitIdentity() {
        let lut = WindowLUT.makeGrayscale(descriptor: descriptor(bits: 8),
                                          window: WindowSettings(center: 128, width: 256))
        #expect(lut.table == (0..<256).map { UInt8($0) })
    }

    /// For n = 12 and 16 the exact value is x · 255 / (2^n − 1); the byte is its floor.
    @Test("12- and 16-bit identity windows floor the exact value", arguments: [12, 16])
    func wideIdentity(bits: Int) {
        let lut = WindowLUT.makeGrayscale(
            descriptor: descriptor(bits: bits),
            window: WindowSettings(center: Double(1 << (bits - 1)), width: Double(1 << bits)))
        let top = (1 << bits) - 1
        for x in 0...top {
            #expect(Int(lut.table[x]) == x * 255 / top, "x = \(x)")
        }
    }

    /// MONOCHROME1 is the same identity, inverted after the VOI (C.7.6.3.1.2).
    @Test("MONOCHROME1 identity window mirrors exactly")
    func monochrome1Identity() {
        let lut = WindowLUT.makeGrayscale(descriptor: descriptor(bits: 8, photometric: .monochrome1),
                                          window: WindowSettings(center: 128, width: 256))
        #expect(lut.table == (0..<256).map { UInt8(255 - $0) })
    }

    @Test("displayByte floors, clamps and absorbs only rounding error")
    func displayByte() {
        #expect(WindowLUT.displayByte(0) == 0)
        #expect(WindowLUT.displayByte(1) == 255)
        #expect(WindowLUT.displayByte(-0.5) == 0)
        #expect(WindowLUT.displayByte(1.5) == 255)
        #expect(WindowLUT.displayByte(1.0 / 255.0 - 1e-15) == 1)      // an ulp-level miss of 1
        #expect(WindowLUT.displayByte(1.0 / 255.0 - 1e-7) == 0)       // a real value below 1
        #expect(WindowLUT.displayByte(128.9 / 255.0) == 128)
    }
}
