import Testing
import Foundation
@testable import DICOMCore

@Suite("PhotometricInterpretation Tests")
struct PhotometricInterpretationTests {
    
    // MARK: - Parsing Tests
    
    @Test("Parse MONOCHROME1")
    func testParseMonochrome1() {
        let pi = PhotometricInterpretation.parse("MONOCHROME1")
        #expect(pi == .monochrome1)
    }
    
    @Test("Parse MONOCHROME2")
    func testParseMonochrome2() {
        let pi = PhotometricInterpretation.parse("MONOCHROME2")
        #expect(pi == .monochrome2)
    }
    
    @Test("Parse RGB")
    func testParseRGB() {
        let pi = PhotometricInterpretation.parse("RGB")
        #expect(pi == .rgb)
    }
    
    @Test("Parse PALETTE COLOR")
    func testParsePaletteColor() {
        let pi = PhotometricInterpretation.parse("PALETTE COLOR")
        #expect(pi == .paletteColor)
    }
    
    @Test("Parse YBR_FULL")
    func testParseYBRFull() {
        let pi = PhotometricInterpretation.parse("YBR_FULL")
        #expect(pi == .ybrFull)
    }
    
    @Test("Parse with whitespace")
    func testParseWithWhitespace() {
        let pi = PhotometricInterpretation.parse("  MONOCHROME2  ")
        #expect(pi == .monochrome2)
    }
    
    @Test("Parse invalid returns nil")
    func testParseInvalidReturnsNil() {
        let pi = PhotometricInterpretation.parse("INVALID")
        #expect(pi == nil)
    }
    
    // MARK: - Property Tests
    
    @Test("isMonochrome for MONOCHROME1")
    func testIsMonochromeForMonochrome1() {
        #expect(PhotometricInterpretation.monochrome1.isMonochrome == true)
        #expect(PhotometricInterpretation.monochrome1.isColor == false)
    }
    
    @Test("isMonochrome for MONOCHROME2")
    func testIsMonochromeForMonochrome2() {
        #expect(PhotometricInterpretation.monochrome2.isMonochrome == true)
        #expect(PhotometricInterpretation.monochrome2.isColor == false)
    }
    
    @Test("isColor for RGB")
    func testIsColorForRGB() {
        #expect(PhotometricInterpretation.rgb.isMonochrome == false)
        #expect(PhotometricInterpretation.rgb.isColor == true)
    }
    
    @Test("isColor for PALETTE COLOR")
    func testIsColorForPaletteColor() {
        #expect(PhotometricInterpretation.paletteColor.isMonochrome == false)
        #expect(PhotometricInterpretation.paletteColor.isColor == true)
    }
    
    @Test("isPaletteColor for PALETTE COLOR")
    func testIsPaletteColorForPaletteColor() {
        #expect(PhotometricInterpretation.paletteColor.isPaletteColor == true)
        #expect(PhotometricInterpretation.rgb.isPaletteColor == false)
        #expect(PhotometricInterpretation.monochrome2.isPaletteColor == false)
    }
    
    @Test("expectedSamplesPerPixel for monochrome")
    func testExpectedSamplesPerPixelForMonochrome() {
        #expect(PhotometricInterpretation.monochrome1.expectedSamplesPerPixel == 1)
        #expect(PhotometricInterpretation.monochrome2.expectedSamplesPerPixel == 1)
    }
    
    @Test("expectedSamplesPerPixel for color")
    func testExpectedSamplesPerPixelForColor() {
        #expect(PhotometricInterpretation.rgb.expectedSamplesPerPixel == 3)
        #expect(PhotometricInterpretation.ybrFull.expectedSamplesPerPixel == 3)
    }
    
    @Test("expectedSamplesPerPixel for paletteColor is 1")
    func testExpectedSamplesPerPixelForPaletteColor() {
        // PALETTE COLOR has 1 sample per pixel - the pixel value is an index into the lookup tables
        // Reference: DICOM PS3.3 C.7.6.3.1.1
        #expect(PhotometricInterpretation.paletteColor.expectedSamplesPerPixel == 1)
    }
    
    // MARK: - Equatable and Hashable
    
    @Test("Equality")
    func testEquality() {
        #expect(PhotometricInterpretation.monochrome2 == PhotometricInterpretation.monochrome2)
        #expect(PhotometricInterpretation.monochrome1 != PhotometricInterpretation.monochrome2)
    }
    
    @Test("Hashable")
    func testHashable() {
        var set = Set<PhotometricInterpretation>()
        set.insert(.monochrome1)
        set.insert(.monochrome2)
        set.insert(.monochrome1)
        #expect(set.count == 2)
    }

    // MARK: - XYB (PS3.3 2026a C.7.6.3.1.2, Sup 232)

    @Test("Parse XYB")
    func testParseXYB() {
        #expect(PhotometricInterpretation.parse("XYB") == .xyb)
        #expect(PhotometricInterpretation.xyb.rawValue == "XYB")
    }

    @Test("XYB is a 3-sample color model, not YBR or palette")
    func testXYBProperties() {
        let pi = PhotometricInterpretation.xyb
        #expect(pi.isColor)
        #expect(!pi.isMonochrome)
        #expect(!pi.isYBR)
        #expect(!pi.isPaletteColor)
        #expect(pi.expectedSamplesPerPixel == 3)
    }
}
