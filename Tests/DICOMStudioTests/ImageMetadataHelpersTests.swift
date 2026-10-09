// ImageMetadataHelpersTests.swift
// DICOMStudioTests
//
// Tests for ImageMetadataHelpers

import Testing
@testable import DICOMStudio
import DICOMCore
import Foundation

@Suite("ImageMetadataHelpers Tests")
struct ImageMetadataHelpersTests {

    // MARK: - dimensionsText

    @Test("Dimensions text for square image")
    func testDimensionsSquare() {
        #expect(ImageMetadataHelpers.dimensionsText(columns: 512, rows: 512) == "512 × 512")
    }

    @Test("Dimensions text for rectangular image")
    func testDimensionsRectangular() {
        #expect(ImageMetadataHelpers.dimensionsText(columns: 1024, rows: 768) == "1024 × 768")
    }

    @Test("Dimensions text for small image")
    func testDimensionsSmall() {
        #expect(ImageMetadataHelpers.dimensionsText(columns: 64, rows: 64) == "64 × 64")
    }

    // MARK: - bitDepthText

    @Test("Bit depth for 16/12/11")
    func testBitDepth16_12() {
        #expect(ImageMetadataHelpers.bitDepthText(bitsAllocated: 16, bitsStored: 12, highBit: 11) == "16 / 12 / 11")
    }

    @Test("Bit depth for 8/8/7")
    func testBitDepth8_8() {
        #expect(ImageMetadataHelpers.bitDepthText(bitsAllocated: 8, bitsStored: 8, highBit: 7) == "8 / 8 / 7")
    }

    @Test("Bit depth for 16/16/15")
    func testBitDepth16_16() {
        #expect(ImageMetadataHelpers.bitDepthText(bitsAllocated: 16, bitsStored: 16, highBit: 15) == "16 / 16 / 15")
    }

    // MARK: - pixelRepresentationText

    @Test("Signed pixel representation")
    func testPixelRepSigned() {
        #expect(ImageMetadataHelpers.pixelRepresentationText(isSigned: true) == "Signed")
    }

    @Test("Unsigned pixel representation")
    func testPixelRepUnsigned() {
        #expect(ImageMetadataHelpers.pixelRepresentationText(isSigned: false) == "Unsigned")
    }

    // MARK: - samplesText

    @Test("Single sample text")
    func testSamplesSingle() {
        #expect(ImageMetadataHelpers.samplesText(samplesPerPixel: 1, planarConfiguration: 0) == "1")
    }

    @Test("Three samples color-by-pixel")
    func testSamplesColorByPixel() {
        #expect(ImageMetadataHelpers.samplesText(samplesPerPixel: 3, planarConfiguration: 0) == "3 (color-by-pixel)")
    }

    @Test("Three samples color-by-plane")
    func testSamplesColorByPlane() {
        #expect(ImageMetadataHelpers.samplesText(samplesPerPixel: 3, planarConfiguration: 1) == "3 (color-by-plane)")
    }

    // MARK: - photometricLabel

    @Test("MONOCHROME1 label")
    func testPhotometricMono1() {
        #expect(ImageMetadataHelpers.photometricLabel(for: "MONOCHROME1") == "Monochrome 1 (inverted)")
    }

    @Test("MONOCHROME2 label")
    func testPhotometricMono2() {
        #expect(ImageMetadataHelpers.photometricLabel(for: "MONOCHROME2") == "Monochrome 2")
    }

    @Test("RGB label")
    func testPhotometricRGB() {
        #expect(ImageMetadataHelpers.photometricLabel(for: "RGB") == "RGB Color")
    }

    @Test("PALETTE COLOR label")
    func testPhotometricPalette() {
        #expect(ImageMetadataHelpers.photometricLabel(for: "PALETTE COLOR") == "Palette Color")
    }

    @Test("YBR_FULL label")
    func testPhotometricYBR() {
        #expect(ImageMetadataHelpers.photometricLabel(for: "YBR_FULL") == "YBR Full")
    }

    @Test("YBR_FULL_422 label")
    func testPhotometricYBR422() {
        #expect(ImageMetadataHelpers.photometricLabel(for: "YBR_FULL_422") == "YBR Full 4:2:2")
    }

    @Test("YBR_PARTIAL_422 label")
    func testPhotometricYBRPartial422() {
        #expect(ImageMetadataHelpers.photometricLabel(for: "YBR_PARTIAL_422") == "YBR Partial 4:2:2")
    }

    @Test("YBR_PARTIAL_420 label")
    func testPhotometricYBRPartial420() {
        #expect(ImageMetadataHelpers.photometricLabel(for: "YBR_PARTIAL_420") == "YBR Partial 4:2:0")
    }

    @Test("YBR_ICT label")
    func testPhotometricYBRICT() {
        #expect(ImageMetadataHelpers.photometricLabel(for: "YBR_ICT") == "YBR ICT (JPEG 2000)")
    }

    @Test("YBR_RCT label")
    func testPhotometricYBRRCT() {
        #expect(ImageMetadataHelpers.photometricLabel(for: "YBR_RCT") == "YBR RCT (JPEG 2000 Lossless)")
    }

    @Test("XYB label (D11)")
    func testPhotometricXYB() {
        #expect(ImageMetadataHelpers.photometricLabel(for: "XYB") == "XYB (JPEG XL)")
    }

    @Test("Every DICOMCore photometric interpretation has a label of its own")
    func testEveryPhotometricTermHasALabel() {
        // The PS3.3 2026a C.7.6.3.1.2 Defined Terms DICOMCore carries (all but the
        // 2001-retired HSV, ARGB, CMYK); each label must differ from the raw term.
        let terms: [PhotometricInterpretation] = [
            .monochrome1, .monochrome2, .paletteColor, .rgb, .ybrFull, .ybrFull422,
            .ybrPartial422, .ybrPartial420, .ybrICT, .ybrRCT, .xyb,
        ]
        #expect(terms.count == 11)
        for term in terms {
            #expect(ImageMetadataHelpers.photometricLabel(for: term.rawValue) != term.rawValue, "\(term.rawValue)")
        }
        for retired in ["HSV", "ARGB", "CMYK"] {
            #expect(ImageMetadataHelpers.photometricLabel(for: retired) == retired)
        }
    }

    @Test("Unknown interpretation returns as-is")
    func testPhotometricUnknown() {
        #expect(ImageMetadataHelpers.photometricLabel(for: "CUSTOM") == "CUSTOM")
    }

    @Test("Case insensitive photometric label")
    func testPhotometricCaseInsensitive() {
        #expect(ImageMetadataHelpers.photometricLabel(for: "monochrome2") == "Monochrome 2")
        #expect(ImageMetadataHelpers.photometricLabel(for: "rgb") == "RGB Color")
    }

    // MARK: - windowLevelText

    @Test("Window level text integer values")
    func testWindowLevelInteger() {
        #expect(ImageMetadataHelpers.windowLevelText(center: 40, width: 400) == "C: 40 W: 400")
    }

    @Test("Window level text decimal values")
    func testWindowLevelDecimal() {
        #expect(ImageMetadataHelpers.windowLevelText(center: 40.5, width: 400.2) == "C: 40.5 W: 400.2")
    }

    @Test("Window level text negative center")
    func testWindowLevelNegative() {
        let text = ImageMetadataHelpers.windowLevelText(center: -600, width: 1500)
        #expect(text == "C: -600 W: 1500")
    }

    // MARK: - frameText

    @Test("Frame text single frame")
    func testFrameTextSingle() {
        #expect(ImageMetadataHelpers.frameText(current: 1, total: 1) == "Frame 1 / 1")
    }

    @Test("Frame text multi-frame")
    func testFrameTextMulti() {
        #expect(ImageMetadataHelpers.frameText(current: 45, total: 120) == "Frame 45 / 120")
    }

    // MARK: - transferSyntaxLabel (D9: names follow DICOMCore, PS3.6 2026a Table A-1)

    @Test("Short labels come from DICOMCore's shortName, never a hand-spelled name")
    func testTransferSyntaxLabelIsCoreShortName() {
        for ts in TransferSyntax.allKnown {
            #expect(ImageMetadataHelpers.transferSyntaxLabel(for: ts.uid) == ts.shortName, "\(ts.uid)")
            #expect(ImageMetadataHelpers.transferSyntaxLabel(for: ts.uid) != ts.uid,
                    "every registered syntax has a label, not a bare UID")
        }
        #expect(ImageMetadataHelpers.transferSyntaxLabel(for: "1.2.840.10008.1.2.4.91") == "JPEG 2000")
        #expect(ImageMetadataHelpers.transferSyntaxLabel(for: "1.2.840.10008.1.2.4.110") == "JPEG XL Lossless")
    }

    @Test("Unknown or empty UIDs are shown as they are")
    func testTransferSyntaxLabelUnknown() {
        #expect(ImageMetadataHelpers.transferSyntaxLabel(for: "1.2.3.4") == "1.2.3.4")
        #expect(ImageMetadataHelpers.transferSyntaxLabel(for: "") == "Unknown")
        #expect(ImageMetadataHelpers.transferSyntaxStandardName(for: "1.2.3.4") == "1.2.3.4")
        #expect(ImageMetadataHelpers.transferSyntaxStandardName(for: "") == "Unknown")
    }

    @Test("The standard name is the PS3.6 2026a Table A-1 name")
    func testTransferSyntaxStandardName() {
        // PS3.6 2026a Table A-1, rows 1.2.840.10008.1.2.4.110 / .90 / .201 / .70.
        #expect(ImageMetadataHelpers.transferSyntaxStandardName(for: "1.2.840.10008.1.2.4.110")
                == "JPEG XL Lossless")
        #expect(ImageMetadataHelpers.transferSyntaxStandardName(for: "1.2.840.10008.1.2.4.90")
                == "JPEG 2000 Image Compression (Lossless Only)")
        #expect(ImageMetadataHelpers.transferSyntaxStandardName(for: "1.2.840.10008.1.2.4.201")
                == "High-Throughput JPEG 2000 Image Compression (Lossless Only)")
        #expect(ImageMetadataHelpers.transferSyntaxStandardName(for: "1.2.840.10008.1.2.4.70")
                == "JPEG Lossless, Non-Hierarchical, First-Order Prediction (Process 14 [Selection Value 1]): "
                   + "Default Transfer Syntax for Lossless JPEG Image Compression")
        for ts in TransferSyntax.allKnown {
            #expect(ImageMetadataHelpers.transferSyntaxStandardName(for: ts.uid) == ts.displayName, "\(ts.uid)")
        }
    }

    // MARK: - memorySizeText

    @Test("Memory size zero bytes")
    func testMemorySizeZero() {
        let text = ImageMetadataHelpers.memorySizeText(totalBytes: 0)
        #expect(text.contains("0") || text.contains("Zero"))
    }

    @Test("Memory size large")
    func testMemorySizeLarge() {
        let text = ImageMetadataHelpers.memorySizeText(totalBytes: 50 * 1024 * 1024)
        #expect(!text.isEmpty)
    }
}
