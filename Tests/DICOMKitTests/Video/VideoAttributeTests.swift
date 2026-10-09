//
// VideoAttributeTests.swift
// DICOMKit
//
// Copyright © 2026 DICOMKit. All rights reserved.
//

import XCTest
@testable import DICOMKit
@testable import DICOMCore

/// Asserts the Video IOD emits every mandatory module attribute with the value the
/// standard requires, rather than a plausible-looking default.
///
/// Reference: PS3.3 A.32.5.3 - Video Endoscopic Image IOD module table
/// Reference: PS3.5 Sections 8.2.7, 8.2.10, 8.2.11 - video encoding constraints
final class VideoAttributeTests: XCTestCase {

    private func makeDataSet(
        configure: (VideoBuilder) -> VideoBuilder = { $0 }
    ) throws -> DataSet {
        let builder = VideoBuilder(
            videoType: .endoscopic,
            rows: 1080,
            columns: 1920,
            numberOfFrames: 300,
            studyInstanceUID: "1.2.3.4.5",
            seriesInstanceUID: "1.2.3.4.5.6"
        )
        return try configure(builder).buildDataSet()
    }

    // MARK: - Multi-frame Module (PS3.3 C.7.6.6)

    func test_frameIncrementPointer_isPresentAndPointsAtFrameTime() throws {
        // Type 1 in the Multi-frame Module: unconditionally mandatory, VR AT,
        // pointing at Frame Time (0018,1063).
        let dataSet = try makeDataSet { $0.setFrameRate(30) }

        let element = try XCTUnwrap(dataSet[.frameIncrementPointer],
                                    "FrameIncrementPointer (0028,0009) is Type 1")
        XCTAssertEqual(element.vr, .AT)
        XCTAssertEqual(element.attributeTagValue, .frameTime)
        XCTAssertEqual(element.valueData.count, 4, "One AT value is 4 bytes")
    }

    func test_frameIncrementPointer_encodesGroupThenElementLittleEndian() throws {
        let dataSet = try makeDataSet()
        let element = try XCTUnwrap(dataSet[.frameIncrementPointer])
        // FrameTime is (0018,1063): group 0x0018 then element 0x1063, each LE.
        XCTAssertEqual(Array(element.valueData), [0x18, 0x00, 0x63, 0x10])
    }

    func test_numberOfFrames_isPresent() throws {
        let dataSet = try makeDataSet()
        XCTAssertEqual(dataSet[.numberOfFrames]?.integerStringValue?.value, 300)
    }

    // MARK: - Cine Module (PS3.3 C.7.6.5)

    func test_frameTime_alwaysEmitted_becausePointerPointsAtIt() throws {
        // FrameTime is Type 1C, and the condition holds: FrameIncrementPointer
        // points at it. It must be present even when the caller sets no rate.
        let dataSet = try makeDataSet()
        let frameTime = try XCTUnwrap(dataSet[.frameTime]?.decimalStringValue?.value)
        XCTAssertGreaterThan(frameTime, 0)
    }

    func test_frameTime_derivedFromFrameRate() throws {
        let dataSet = try makeDataSet { $0.setFrameRate(25) }
        let frameTime = try XCTUnwrap(dataSet[.frameTime]?.decimalStringValue?.value)
        XCTAssertEqual(frameTime, 40.0, accuracy: 0.0001, "25 fps is 40 ms per frame")
    }

    func test_frameTime_fitsDecimalStringLimit() throws {
        // 29.97 fps gives 33.366666..., which must be truncated to fit DS's 16-byte
        // limit rather than written at full Double precision.
        let dataSet = try makeDataSet { $0.setFrameTime(1000.0 / (30000.0 / 1001.0)) }
        let element = try XCTUnwrap(dataSet[.frameTime])
        XCTAssertLessThanOrEqual(element.valueData.count, 16,
                                 "DS values are limited to 16 bytes (PS3.5 Table 6.2-1)")
        let value = try XCTUnwrap(element.decimalStringValue?.value)
        XCTAssertEqual(value, 33.3667, accuracy: 0.001)
    }

    func test_cineRate_andRecommendedDisplayFrameRate_emittedWhenKnown() throws {
        let dataSet = try makeDataSet { $0.setFrameRate(60) }
        XCTAssertEqual(dataSet[.cineRate]?.integerStringValue?.value, 60)
        XCTAssertEqual(dataSet[.recommendedDisplayFrameRate]?.integerStringValue?.value, 60)
    }

    // MARK: - Image Pixel Module (PS3.3 C.7.6.3) and fixed values

    func test_fixedValueAttributes_matchStandard() throws {
        let dataSet = try makeDataSet()

        // "shall be 3" / "shall be 0" / "shall be 0" per PS3.5 8.2.7.
        XCTAssertEqual(dataSet[.samplesPerPixel]?.uint16Value, 3)
        XCTAssertEqual(dataSet[.planarConfiguration]?.uint16Value, 0)
        XCTAssertEqual(dataSet[.pixelRepresentation]?.uint16Value, 0)
        XCTAssertEqual(dataSet.string(for: .photometricInterpretation), "YBR_PARTIAL_420")
    }

    func test_planarConfiguration_alwaysEmittedForColourVideo() throws {
        // It is required whenever SamplesPerPixel > 1, so it must not be left to
        // an optional setter the caller might skip.
        let dataSet = try makeDataSet()
        XCTAssertNotNil(dataSet[.planarConfiguration],
                        "PlanarConfiguration is required when SamplesPerPixel > 1")
    }

    func test_pixelAspectRatio_isAbsent() throws {
        // PS3.5 8.2.7: "Pixel Aspect Ratio (0028,0034) shall be absent." The video
        // transfer syntaxes fix the Sampling Aspect Ratio at 1:1.
        let dataSet = try makeDataSet()
        XCTAssertNil(dataSet[.pixelAspectRatio],
                     "PixelAspectRatio (0028,0034) shall be absent")
    }

    // MARK: - Bit depth (PS3.5 8.2.7 / 8.2.10 / 8.2.11)

    func test_bitDepth_defaultsToEightBit() throws {
        let dataSet = try makeDataSet()
        XCTAssertEqual(dataSet[.bitsAllocated]?.uint16Value, 8)
        XCTAssertEqual(dataSet[.bitsStored]?.uint16Value, 8)
        XCTAssertEqual(dataSet[.highBit]?.uint16Value, 7)
    }

    func test_bitDepth_hevcMain10_isSixteenTenNine() throws {
        // BitsAllocated is 16, not 10: DICOM allocates on byte boundaries.
        let dataSet = try makeDataSet { $0.setBitDepthForLumaBitDepth(10) }
        XCTAssertEqual(dataSet[.bitsAllocated]?.uint16Value, 16)
        XCTAssertEqual(dataSet[.bitsStored]?.uint16Value, 10)
        XCTAssertEqual(dataSet[.highBit]?.uint16Value, 9)
    }

    func test_videoBitDepth_forLumaBitDepth_rejectsUnrepresentable() {
        XCTAssertEqual(VideoBitDepth.forLumaBitDepth(8), .eightBit)
        XCTAssertEqual(VideoBitDepth.forLumaBitDepth(10), .tenBit)
        // 12-bit is not carried by any DICOM video transfer syntax; returning nil
        // makes the caller reject rather than silently mislabel the object.
        XCTAssertNil(VideoBitDepth.forLumaBitDepth(12))
        XCTAssertNil(VideoBitDepth.forLumaBitDepth(0))
    }

    // MARK: - VL Image Module (PS3.3 C.8.12)

    func test_imageType_isPresentAsTypeOne() throws {
        let dataSet = try makeDataSet()
        let element = try XCTUnwrap(dataSet[.imageType],
                                    "ImageType (0008,0008) is Type 1 in the VL Image Module")
        XCTAssertEqual(element.stringValues, ["ORIGINAL", "PRIMARY"])
        XCTAssertFalse(element.valueData.isEmpty, "A Type 1 attribute must have a value")
    }

    /// D180: text is written as UTF-8, so Specific Character Set (0008,0005), Type 1C
    /// "Required if an expanded or replacement character set is used" (PS3.3 2026a
    /// Table C.12-1), is ISO_IR 192 (Table C.12-5) when a value is not ASCII.
    func test_specificCharacterSet_isUTF8ForNonASCIIText() throws {
        let dataSet = try makeDataSet { $0.setPatientName("Müller^Jörg") }
        XCTAssertEqual(dataSet.string(for: .specificCharacterSet), "ISO_IR 192")
        XCTAssertEqual(dataSet.string(for: .patientName), "Müller^Jörg")
        XCTAssertNil(try makeDataSet { $0.setPatientName("DOE^John") }[.specificCharacterSet])
    }

    func test_imageType_overridable() throws {
        let dataSet = try makeDataSet { $0.setImageType(["DERIVED", "SECONDARY"]) }
        XCTAssertEqual(dataSet[.imageType]?.stringValues, ["DERIVED", "SECONDARY"])
    }

    func test_lossyImageCompression_isAlwaysOne() throws {
        // Type 2 per PS3.3 C.8.12, and video is always lossy.
        let dataSet = try makeDataSet()
        XCTAssertEqual(dataSet.string(for: .lossyImageCompression), "01")
    }

    func test_lossyImageCompressionMethod_perCodec() throws {
        let expected: [(VideoCodec, String)] = [
            (.mpeg2, "ISO_13818_2"),
            (.h264, "ISO_14496_10"),
            (.h265, "ISO_23008_2"),
        ]
        for (codec, method) in expected {
            let dataSet = try makeDataSet { $0.setLossyCompression(codec: codec) }
            XCTAssertEqual(dataSet.string(for: .lossyImageCompressionMethod), method)
        }
    }

    // MARK: - Type 2 attributes are present even when unknown

    func test_typeTwoAttributes_emittedZeroLengthWhenUnset() throws {
        let dataSet = try makeDataSet()

        // Type 2 means "present, possibly empty" — absent is non-conformant.
        let typeTwoTags: [(Tag, String)] = [
            (.patientName, "PatientName"),
            (.patientID, "PatientID"),
            (.patientBirthDate, "PatientBirthDate"),
            (.patientSex, "PatientSex"),
            (.studyDate, "StudyDate"),
            (.studyTime, "StudyTime"),
            (.referringPhysicianName, "ReferringPhysicianName"),
            (.studyID, "StudyID"),
            (.accessionNumber, "AccessionNumber"),
            (.seriesNumber, "SeriesNumber"),
            (.instanceNumber, "InstanceNumber"),
            (.manufacturer, "Manufacturer"),
            (.patientOrientation, "PatientOrientation"),
        ]

        for (tag, name) in typeTwoTags {
            let element = try XCTUnwrap(dataSet[tag], "\(name) is Type 2 and must be present")
            XCTAssertEqual(element.valueData.count, 0,
                           "\(name) should be zero-length when unset, not padded")
        }
    }

    func test_acquisitionContextSequence_isPresentAndMayBeEmpty() throws {
        // Type 2 in the Acquisition Context Module, and an empty sequence is legal.
        let dataSet = try makeDataSet()
        let element = try XCTUnwrap(dataSet[.acquisitionContextSequence],
                                    "AcquisitionContextSequence (0040,0555) is Type 2")
        XCTAssertEqual(element.vr, .SQ)
        XCTAssertEqual(element.sequenceItemCount, 0)
    }

    func test_modality_isPresentAsTypeOne() throws {
        // Type 1 in the General Series Module; defaults from the video type.
        let dataSet = try makeDataSet()
        XCTAssertEqual(dataSet.string(for: .modality), "ES")
    }

    func test_typeTwoAttributes_carryValuesWhenSet() throws {
        let dataSet = try makeDataSet {
            $0.setPatientName("Smith^John")
                .setPatientID("MRN-1")
                .setManufacturer("Acme Endoscopy")
                .setStudyID("ST-1")
                .setAccessionNumber("ACC-1")
                .setReferringPhysicianName("Jones^Mary")
                .setPatientSex("F")
                .setInstanceNumber(7)
                .setSeriesNumber(2)
        }

        XCTAssertEqual(dataSet.string(for: .patientName), "Smith^John")
        XCTAssertEqual(dataSet.string(for: .patientID), "MRN-1")
        XCTAssertEqual(dataSet.string(for: .manufacturer), "Acme Endoscopy")
        XCTAssertEqual(dataSet.string(for: .studyID), "ST-1")
        XCTAssertEqual(dataSet.string(for: .accessionNumber), "ACC-1")
        XCTAssertEqual(dataSet.string(for: .referringPhysicianName), "Jones^Mary")
        XCTAssertEqual(dataSet.string(for: .patientSex), "F")
        XCTAssertEqual(dataSet[.instanceNumber]?.integerStringValue?.value, 7)
        XCTAssertEqual(dataSet[.seriesNumber]?.integerStringValue?.value, 2)
    }

    // MARK: - Round trip through a real file

    func test_mandatoryAttributes_surviveFileRoundTrip() throws {
        let video = try VideoBuilder(
            videoType: .endoscopic,
            rows: 1080,
            columns: 1920,
            numberOfFrames: 300,
            studyInstanceUID: "1.2.3.4.5",
            seriesInstanceUID: "1.2.3.4.5.6"
        )
        .setFrameRate(30)
        .setPixelData(Data(repeating: 0xAB, count: 512))
        .build()

        let file = DICOMFile.create(
            dataSet: video.toDataSet(),
            sopClassUID: video.sopClassUID,
            sopInstanceUID: video.sopInstanceUID,
            transferSyntaxUID: TransferSyntax.mpeg4AVCHP41.uid
        )
        let readFile = try DICOMFile.read(from: try file.write())

        XCTAssertEqual(readFile.dataSet[.imageType]?.stringValues, ["ORIGINAL", "PRIMARY"])
        XCTAssertEqual(readFile.dataSet[.frameIncrementPointer]?.attributeTagValue, .frameTime)
        XCTAssertEqual(readFile.dataSet.string(for: .lossyImageCompression), "01")
        XCTAssertEqual(readFile.dataSet.string(for: .photometricInterpretation), "YBR_PARTIAL_420")
        XCTAssertNil(readFile.dataSet[.pixelAspectRatio])
        XCTAssertNotNil(readFile.dataSet[.acquisitionContextSequence])
    }

    // MARK: - Decimal string formatting

    func test_decimalString_staysWithinSixteenBytes() {
        let awkwardValues: [Double] = [
            1000.0 / (30000.0 / 1001.0),   // 29.97 fps
            1000.0 / (24000.0 / 1001.0),   // 23.976 fps
            1.0 / 3.0,
            123456789.123456789,
            -1.0 / 7.0,
        ]
        for value in awkwardValues {
            let formatted = Video.decimalString(value)
            XCTAssertLessThanOrEqual(formatted.utf8.count, 16,
                                     "\(formatted) exceeds the 16-byte DS limit")
        }
    }

    func test_decimalString_rendersWholeNumbersWithoutFraction() {
        XCTAssertEqual(Video.decimalString(40.0), "40")
        XCTAssertEqual(Video.decimalString(0.0), "0")
        XCTAssertEqual(Video.decimalString(-5.0), "-5")
    }
}
