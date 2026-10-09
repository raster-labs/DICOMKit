// ThumbnailHelpersTests.swift
// DICOMStudioTests
//
// Tests for ThumbnailHelpers

import Testing
@testable import DICOMStudio
import DICOMCore
import Foundation

@Suite("ThumbnailHelpers Tests")
struct ThumbnailHelpersTests {

    // MARK: - thumbnailDimensions Tests

    @Test("Scales landscape image to fit max size")
    func testThumbnailDimensionsLandscape() {
        let dims = ThumbnailHelpers.thumbnailDimensions(
            imageWidth: 512,
            imageHeight: 256,
            maxSize: 128
        )
        #expect(dims != nil)
        #expect(dims!.width == 128)
        #expect(dims!.height == 64)
    }

    @Test("Scales portrait image to fit max size")
    func testThumbnailDimensionsPortrait() {
        let dims = ThumbnailHelpers.thumbnailDimensions(
            imageWidth: 256,
            imageHeight: 512,
            maxSize: 128
        )
        #expect(dims != nil)
        #expect(dims!.width == 64)
        #expect(dims!.height == 128)
    }

    @Test("Scales square image to fit max size")
    func testThumbnailDimensionsSquare() {
        let dims = ThumbnailHelpers.thumbnailDimensions(
            imageWidth: 512,
            imageHeight: 512,
            maxSize: 128
        )
        #expect(dims != nil)
        #expect(dims!.width == 128)
        #expect(dims!.height == 128)
    }

    @Test("Returns original dimensions if smaller than max")
    func testThumbnailDimensionsSmallerThanMax() {
        let dims = ThumbnailHelpers.thumbnailDimensions(
            imageWidth: 64,
            imageHeight: 32,
            maxSize: 128
        )
        #expect(dims != nil)
        #expect(dims!.width == 64)
        #expect(dims!.height == 32)
    }

    @Test("Returns nil for zero width")
    func testThumbnailDimensionsZeroWidth() {
        let dims = ThumbnailHelpers.thumbnailDimensions(
            imageWidth: 0,
            imageHeight: 256,
            maxSize: 128
        )
        #expect(dims == nil)
    }

    @Test("Returns nil for zero height")
    func testThumbnailDimensionsZeroHeight() {
        let dims = ThumbnailHelpers.thumbnailDimensions(
            imageWidth: 256,
            imageHeight: 0,
            maxSize: 128
        )
        #expect(dims == nil)
    }

    @Test("Returns nil for zero max size")
    func testThumbnailDimensionsZeroMaxSize() {
        let dims = ThumbnailHelpers.thumbnailDimensions(
            imageWidth: 256,
            imageHeight: 256,
            maxSize: 0
        )
        #expect(dims == nil)
    }

    @Test("Returns nil for negative dimensions")
    func testThumbnailDimensionsNegative() {
        let dims = ThumbnailHelpers.thumbnailDimensions(
            imageWidth: -100,
            imageHeight: 100,
            maxSize: 128
        )
        #expect(dims == nil)
    }

    // MARK: - defaultWindowSettings Tests

    @Test("CT default window settings")
    func testCTWindowSettings() {
        let settings = ThumbnailHelpers.defaultWindowSettings(for: "CT")
        #expect(settings.center == 40.0)
        #expect(settings.width == 400.0)
    }

    @Test("MR default window settings")
    func testMRWindowSettings() {
        let settings = ThumbnailHelpers.defaultWindowSettings(for: "MR")
        #expect(settings.center == 500.0)
        #expect(settings.width == 1000.0)
    }

    @Test("CR default window settings")
    func testCRWindowSettings() {
        let settings = ThumbnailHelpers.defaultWindowSettings(for: "CR")
        #expect(settings.center == 2048.0)
        #expect(settings.width == 4096.0)
    }

    @Test("DX default window settings same as CR")
    func testDXWindowSettings() {
        let cr = ThumbnailHelpers.defaultWindowSettings(for: "CR")
        let dx = ThumbnailHelpers.defaultWindowSettings(for: "DX")
        #expect(cr.center == dx.center)
        #expect(cr.width == dx.width)
    }

    @Test("US default window settings")
    func testUSWindowSettings() {
        let settings = ThumbnailHelpers.defaultWindowSettings(for: "US")
        #expect(settings.center == 128.0)
        #expect(settings.width == 256.0)
    }

    @Test("Unknown modality returns generic defaults")
    func testUnknownModalitySettings() {
        let settings = ThumbnailHelpers.defaultWindowSettings(for: "UNKNOWN")
        #expect(settings.center == 128.0)
        #expect(settings.width == 256.0)
    }

    @Test("Case-insensitive modality matching")
    func testCaseInsensitiveModality() {
        let ct = ThumbnailHelpers.defaultWindowSettings(for: "ct")
        #expect(ct.center == 40.0)
    }

    // MARK: - cacheKey Tests

    @Test("Cache key for default frame")
    func testCacheKeyDefault() {
        let key = ThumbnailHelpers.cacheKey(sopInstanceUID: "1.2.840.1234.5678")
        #expect(key == "1_2_840_1234_5678")
    }

    @Test("Cache key with frame number")
    func testCacheKeyWithFrame() {
        let key = ThumbnailHelpers.cacheKey(sopInstanceUID: "1.2.3", frameNumber: 5)
        #expect(key == "1_2_3_f5")
    }

    @Test("Cache key frame 0 same as default")
    func testCacheKeyFrame0() {
        let key = ThumbnailHelpers.cacheKey(sopInstanceUID: "1.2.3", frameNumber: 0)
        #expect(key == "1_2_3")
    }

    // MARK: - shouldGenerateThumbnail Tests

    @Test("Should generate for valid pixel data")
    func testShouldGenerateThumbnailValid() {
        #expect(ThumbnailHelpers.shouldGenerateThumbnail(
            rows: 512,
            columns: 512,
            photometricInterpretation: "MONOCHROME2"
        ) == true)
    }

    @Test("Should not generate for nil rows")
    func testShouldNotGenerateNilRows() {
        #expect(ThumbnailHelpers.shouldGenerateThumbnail(
            rows: nil,
            columns: 512,
            photometricInterpretation: "MONOCHROME2"
        ) == false)
    }

    @Test("Should not generate for nil columns")
    func testShouldNotGenerateNilColumns() {
        #expect(ThumbnailHelpers.shouldGenerateThumbnail(
            rows: 512,
            columns: nil,
            photometricInterpretation: "MONOCHROME2"
        ) == false)
    }

    @Test("Should not generate for zero rows")
    func testShouldNotGenerateZeroRows() {
        #expect(ThumbnailHelpers.shouldGenerateThumbnail(
            rows: 0,
            columns: 512,
            photometricInterpretation: "MONOCHROME2"
        ) == false)
    }

    @Test("Should not generate for nil photometric")
    func testShouldNotGenerateNilPhotometric() {
        #expect(ThumbnailHelpers.shouldGenerateThumbnail(
            rows: 512,
            columns: 512,
            photometricInterpretation: nil
        ) == false)
    }

    @Test("Should not generate for empty photometric")
    func testShouldNotGenerateEmptyPhotometric() {
        #expect(ThumbnailHelpers.shouldGenerateThumbnail(
            rows: 512,
            columns: 512,
            photometricInterpretation: ""
        ) == false)
    }

    // MARK: - isSupportedPhotometricInterpretation Tests

    @Test("Supported photometric interpretations")
    func testSupportedPhotometric() {
        #expect(ThumbnailHelpers.isSupportedPhotometricInterpretation("MONOCHROME1") == true)
        #expect(ThumbnailHelpers.isSupportedPhotometricInterpretation("MONOCHROME2") == true)
        #expect(ThumbnailHelpers.isSupportedPhotometricInterpretation("RGB") == true)
        #expect(ThumbnailHelpers.isSupportedPhotometricInterpretation("PALETTE COLOR") == true)
        #expect(ThumbnailHelpers.isSupportedPhotometricInterpretation("YBR_FULL") == true)
        #expect(ThumbnailHelpers.isSupportedPhotometricInterpretation("YBR_FULL_422") == true)
        #expect(ThumbnailHelpers.isSupportedPhotometricInterpretation("YBR_PARTIAL_422") == true)
        // D10: the compressed-domain and video terms were missing.
        #expect(ThumbnailHelpers.isSupportedPhotometricInterpretation("YBR_PARTIAL_420") == true)
        #expect(ThumbnailHelpers.isSupportedPhotometricInterpretation("YBR_ICT") == true)
        #expect(ThumbnailHelpers.isSupportedPhotometricInterpretation("YBR_RCT") == true)
        #expect(ThumbnailHelpers.isSupportedPhotometricInterpretation("XYB") == true)
        // Retired in PS3.3-2001 and not in DICOMCore.
        #expect(ThumbnailHelpers.isSupportedPhotometricInterpretation("HSV") == false)
        #expect(ThumbnailHelpers.isSupportedPhotometricInterpretation("ARGB") == false)
        #expect(ThumbnailHelpers.isSupportedPhotometricInterpretation("CMYK") == false)
    }

    @Test("Case-insensitive photometric matching")
    func testCaseInsensitivePhotometric() {
        #expect(ThumbnailHelpers.isSupportedPhotometricInterpretation("monochrome2") == true)
        #expect(ThumbnailHelpers.isSupportedPhotometricInterpretation("rgb") == true)
    }

    @Test("Unsupported photometric interpretations")
    func testUnsupportedPhotometric() {
        #expect(ThumbnailHelpers.isSupportedPhotometricInterpretation("UNKNOWN") == false)
        #expect(ThumbnailHelpers.isSupportedPhotometricInterpretation("") == false)
    }

    // MARK: - Supported Photometric Set

    @Test("Supported set is every PS3.3 2026a C.7.6.3.1.2 Defined Term except the three retired in 2001")
    func testSupportedPhotometricSet() {
        // PS3.3 2026a C.7.6.3.1.2 lists 14 terms; HSV, ARGB and CMYK are "Retired. See PS3.3-2001".
        let expected: Set<String> = [
            "MONOCHROME1", "MONOCHROME2", "PALETTE COLOR", "RGB",
            "YBR_FULL", "YBR_FULL_422", "YBR_PARTIAL_422", "YBR_PARTIAL_420",
            "YBR_ICT", "YBR_RCT", "XYB",
        ]
        #expect(ThumbnailHelpers.supportedPhotometricInterpretations == expected)
        #expect(ThumbnailHelpers.supportedPhotometricInterpretations.count == 11)
        // Built from DICOMCore, so each string parses back to a PhotometricInterpretation.
        for term in ThumbnailHelpers.supportedPhotometricInterpretations {
            #expect(PhotometricInterpretation.parse(term)?.rawValue == term, "\(term)")
        }
    }
}
