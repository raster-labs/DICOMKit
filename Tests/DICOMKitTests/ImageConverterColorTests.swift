//
// ImageConverterColorTests.swift
// DICOMKit
//
// Regression: colour (RGB/RGBA) sources used to fail with
// "Failed to create graphics context" because Core Graphics has no packed
// 24-bit RGB bitmap layout. Colour must convert; alpha composites onto white.
//

import XCTest
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
@testable import DICOMKit
import DICOMCore

final class ImageConverterColorTests: XCTestCase {

    private func writePNG(rgba: [UInt8], width: Int, height: Int) throws -> URL {
        let data = Data(rgba)
        let provider = CGDataProvider(data: data as CFData)!
        let image = CGImage(
            width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
            bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue),
            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent
        )!
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ImageConverterColorTests-\(UUID().uuidString).png")
        let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(dest, image, nil)
        XCTAssertTrue(CGImageDestinationFinalize(dest))
        return url
    }

    private var metadata: ImageConverter.Metadata {
        ImageConverter.Metadata(
            patientName: "DOE^John", patientID: "12345",
            studyUID: ImageConverter.generateUID(), seriesUID: ImageConverter.generateUID(),
            instanceNumber: 1
        )
    }

    func test_rgbaPNG_convertsToRGBSecondaryCapture_compositedOnWhite() throws {
        // Row 0: opaque red, opaque green. Row 1: opaque blue, fully transparent.
        let rgba: [UInt8] = [
            255, 0, 0, 255,   0, 255, 0, 255,
            0, 0, 255, 255,   0, 0, 0, 0,
        ]
        let url = try writePNG(rgba: rgba, width: 2, height: 2)
        defer { try? FileManager.default.removeItem(at: url) }

        let bytes = try ImageConverter.secondaryCaptureData(imageURL: url, metadata: metadata, useExif: false)
        let ds = try DICOMFile.read(from: bytes).dataSet

        XCTAssertEqual(ds.uint16(for: .samplesPerPixel), 3)
        XCTAssertEqual(ds.string(for: .photometricInterpretation), "RGB")
        XCTAssertEqual(ds.uint16(for: .rows), 2)
        XCTAssertEqual(ds.uint16(for: .columns), 2)

        let pixels = try XCTUnwrap(ds[.pixelData]?.valueData)
        XCTAssertEqual(pixels.count, 2 * 2 * 3, "packed 24-bit RGB, no padding byte")
        XCTAssertEqual([UInt8](pixels), [
            255, 0, 0,   0, 255, 0,
            0, 0, 255,   255, 255, 255,   // transparent → white
        ])
    }

    func test_grayscalePNG_stillConvertsAsMonochrome2() throws {
        let gray: [UInt8] = [0, 128, 255, 64]
        let provider = CGDataProvider(data: Data(gray) as CFData)!
        let image = CGImage(
            width: 2, height: 2, bitsPerComponent: 8, bitsPerPixel: 8, bytesPerRow: 2,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent
        )!
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ImageConverterColorTests-gray-\(UUID().uuidString).png")
        defer { try? FileManager.default.removeItem(at: url) }
        let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(dest, image, nil)
        XCTAssertTrue(CGImageDestinationFinalize(dest))

        let bytes = try ImageConverter.secondaryCaptureData(imageURL: url, metadata: metadata, useExif: false)
        let ds = try DICOMFile.read(from: bytes).dataSet
        XCTAssertEqual(ds.uint16(for: .samplesPerPixel), 1)
        XCTAssertEqual(ds.string(for: .photometricInterpretation), "MONOCHROME2")
        XCTAssertEqual([UInt8](try XCTUnwrap(ds[.pixelData]?.valueData)), gray)
    }

    /// PS3.3 2026a Table A.8-1: every Type 1 attribute of the mandatory modules has a
    /// value and every Type 2 attribute is present (Tables C.7-1, C.7-3, C.7-5a,
    /// C.7-9, C.7-11a, C.8-24, C.12-1).
    func test_secondaryCapture_type1AndType2AttributesComplete() throws {
        let url = try writePNG(rgba: [255, 0, 0, 255, 0, 255, 0, 255, 0, 0, 255, 255, 0, 0, 0, 0], width: 2, height: 2)
        defer { try? FileManager.default.removeItem(at: url) }

        let bytes = try ImageConverter.secondaryCaptureData(imageURL: url, metadata: metadata, useExif: false)
        let ds = try DICOMFile.read(from: bytes).dataSet

        let type1: [Tag] = [.sopClassUID, .sopInstanceUID, .studyInstanceUID, .modality, .seriesInstanceUID,
                            .conversionType, .samplesPerPixel, .photometricInterpretation, .rows, .columns,
                            .bitsAllocated, .bitsStored, .highBit, .pixelRepresentation, .planarConfiguration, .pixelData]
        for tag in type1 {
            let element = try XCTUnwrap(ds[tag], "Type 1 \(tag) missing")
            XCTAssertFalse(element.valueData.isEmpty, "Type 1 \(tag) empty")
        }
        let type2: [Tag] = [.patientName, .patientID, .patientBirthDate, .patientSex,
                            .studyDate, .studyTime, .referringPhysicianName, .studyID, .accessionNumber,
                            .seriesNumber, .instanceNumber, .patientOrientation]
        for tag in type2 {
            XCTAssertNotNil(ds[tag], "Type 2 \(tag) missing")
        }
        XCTAssertEqual(ds.string(for: .sopClassUID), SecondaryCaptureImage.secondaryCaptureImageStorageUID)
        XCTAssertEqual(ds.string(for: .conversionType), "WSD", "Table C.8-24 default term")
        XCTAssertEqual(ds.string(for: .patientBirthDate), "")
        XCTAssertEqual(ds.string(for: .seriesNumber), "")
        XCTAssertEqual(ds.string(for: .patientOrientation), "")
        XCTAssertEqual(ds.string(for: .instanceNumber), "1")
    }

    func test_secondaryCapture_metadataConversionTypeAndType2Values() throws {
        let url = try writePNG(rgba: [255, 0, 0, 255], width: 1, height: 1)
        defer { try? FileManager.default.removeItem(at: url) }

        var meta = metadata
        meta.conversionType = .drawing
        meta.patientBirthDate = DICOMDate(year: 1970, month: 1, day: 2)
        meta.patientSex = "M"
        meta.referringPhysicianName = "Ref^Doc"
        meta.studyID = "S9"
        meta.accessionNumber = "ACC9"
        meta.seriesNumber = 4

        let bytes = try ImageConverter.secondaryCaptureData(imageURL: url, metadata: meta, useExif: false)
        let ds = try DICOMFile.read(from: bytes).dataSet
        XCTAssertEqual(ds.string(for: .conversionType), "DRW")
        XCTAssertEqual(ds.string(for: .patientBirthDate), "19700102")
        XCTAssertEqual(ds.string(for: .patientSex), "M")
        XCTAssertEqual(ds.string(for: .referringPhysicianName), "Ref^Doc")
        XCTAssertEqual(ds.string(for: .studyID), "S9")
        XCTAssertEqual(ds.string(for: .accessionNumber), "ACC9")
        XCTAssertEqual(ds.string(for: .seriesNumber), "4")
    }
}

/// PS3.3 2026a rules ImageConverter applies itself since 2026-10-01 (D166-D168), so
/// DICOMStudio's conversion matches dicom-image.
final class ImageConverterStandardTests: XCTestCase {

    private func grayPNG() throws -> URL {
        let provider = CGDataProvider(data: Data([0, 128, 255, 64]) as CFData)!
        let image = CGImage(
            width: 2, height: 2, bitsPerComponent: 8, bitsPerPixel: 8, bytesPerRow: 2,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ImageConverterStandardTests-\(UUID().uuidString).png")
        let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(dest, image, nil)
        XCTAssertTrue(CGImageDestinationFinalize(dest))
        return url
    }

    private func convert(patientName: String) throws -> DataSet {
        let url = try grayPNG()
        defer { try? FileManager.default.removeItem(at: url) }
        let metadata = ImageConverter.Metadata(
            patientName: patientName, patientID: "12345",
            studyUID: ImageConverter.generateUID(), seriesUID: ImageConverter.generateUID(), instanceNumber: 1)
        return try DICOMFile.read(from: ImageConverter.secondaryCaptureData(
            imageURL: url, metadata: metadata, useExif: false)).dataSet
    }

    /// D166: Specific Character Set (0008,0005) Type 1C, ISO_IR 192 (Tables C.12-1, C.12-5).
    func testNonASCIITextGetsISOIR192() throws {
        let ds = try convert(patientName: "Müller^Jörg")
        XCTAssertEqual(ds.string(for: .specificCharacterSet), "ISO_IR 192")
        XCTAssertEqual(ds.string(for: .patientName), "Müller^Jörg")
        XCTAssertNil(try convert(patientName: "DOE^John")[.specificCharacterSet], "ASCII needs no 1C value")
    }

    /// D167: the converter is the Secondary Capture Device (Table C.8-24); General
    /// Equipment describes the equipment that created the original image (C.8.6.1).
    func testConverterIdentityIsTheSecondaryCaptureDevice() throws {
        let ds = try convert(patientName: "DOE^John")
        XCTAssertEqual(ds.string(for: Tag(group: 0x0018, element: 0x1016)), "DICOMKit")
        XCTAssertEqual(ds.string(for: Tag(group: 0x0018, element: 0x1018)), "DICOMKit ImageConverter")
        XCTAssertEqual(ds.string(for: Tag(group: 0x0018, element: 0x1019)), DICOMFile.implementationVersionName)
        XCTAssertNil(ds[.manufacturer])
        XCTAssertNil(ds[.manufacturerModelName])
        XCTAssertNil(ds[.softwareVersions])
        XCTAssertEqual(ds.string(for: .conversionType), "WSD")
    }

    /// D168: EXIF text written to Study Description is a valid LO (PS3.5 Table 6.2-1:
    /// 64 characters, no backslash, no control characters).
    func testEXIFDescriptionIsALongString() {
        XCTAssertEqual(ImageConverter.longStringValue("Scan\\2\nfront\u{0}"), "Scan/2 front")
        XCTAssertEqual(ImageConverter.longStringValue(String(repeating: "é", count: 80))?.count, 64)
        XCTAssertNil(ImageConverter.longStringValue(" \u{0}\u{0} "))
    }
}
