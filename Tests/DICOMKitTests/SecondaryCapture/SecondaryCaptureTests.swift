//
// SecondaryCaptureTests.swift
// DICOMKit
//
// Created by DICOMKit on 2026-02-09.
// Copyright © 2026 DICOMKit. All rights reserved.
//

import XCTest
@testable import DICOMKit
@testable import DICOMCore

final class SecondaryCaptureTests: XCTestCase {

    // MARK: - SecondaryCaptureType Tests

    func test_secondaryCaptureType_singleFrame_fromSOPClassUID() {
        let type = SecondaryCaptureType(sopClassUID: "1.2.840.10008.5.1.4.1.1.7")
        XCTAssertEqual(type, .singleFrame)
        XCTAssertEqual(type.sopClassUID, "1.2.840.10008.5.1.4.1.1.7")
        XCTAssertEqual(type.defaultModality, "OT")
        XCTAssertEqual(type.displayName, "Secondary Capture")
    }

    func test_secondaryCaptureType_multiframeSingleBit_fromSOPClassUID() {
        let type = SecondaryCaptureType(sopClassUID: "1.2.840.10008.5.1.4.1.1.7.1")
        XCTAssertEqual(type, .multiframeSingleBit)
        XCTAssertEqual(type.sopClassUID, "1.2.840.10008.5.1.4.1.1.7.1")
        XCTAssertEqual(type.displayName, "Multi-frame Single Bit SC")
    }

    func test_secondaryCaptureType_multiframeGrayscaleByte_fromSOPClassUID() {
        let type = SecondaryCaptureType(sopClassUID: "1.2.840.10008.5.1.4.1.1.7.2")
        XCTAssertEqual(type, .multiframeGrayscaleByte)
        XCTAssertEqual(type.sopClassUID, "1.2.840.10008.5.1.4.1.1.7.2")
        XCTAssertEqual(type.displayName, "Multi-frame Grayscale Byte SC")
    }

    func test_secondaryCaptureType_multiframeGrayscaleWord_fromSOPClassUID() {
        let type = SecondaryCaptureType(sopClassUID: "1.2.840.10008.5.1.4.1.1.7.3")
        XCTAssertEqual(type, .multiframeGrayscaleWord)
        XCTAssertEqual(type.sopClassUID, "1.2.840.10008.5.1.4.1.1.7.3")
        XCTAssertEqual(type.displayName, "Multi-frame Grayscale Word SC")
    }

    func test_secondaryCaptureType_multiframeTrueColor_fromSOPClassUID() {
        let type = SecondaryCaptureType(sopClassUID: "1.2.840.10008.5.1.4.1.1.7.4")
        XCTAssertEqual(type, .multiframeTrueColor)
        XCTAssertEqual(type.sopClassUID, "1.2.840.10008.5.1.4.1.1.7.4")
        XCTAssertEqual(type.displayName, "Multi-frame True Color SC")
    }

    func test_secondaryCaptureType_unknown_fromInvalidSOPClassUID() {
        let type = SecondaryCaptureType(sopClassUID: "1.2.3.4.5")
        XCTAssertEqual(type, .unknown)
        XCTAssertEqual(type.sopClassUID, "")
        XCTAssertEqual(type.defaultModality, "OT")
        XCTAssertEqual(type.displayName, "Unknown SC")
    }

    func test_secondaryCaptureType_defaultPixelCharacteristics() {
        // Single frame - grayscale 8-bit
        let sfDefaults = SecondaryCaptureType.singleFrame.defaultPixelCharacteristics
        XCTAssertEqual(sfDefaults.samplesPerPixel, 1)
        XCTAssertEqual(sfDefaults.bitsAllocated, 8)
        XCTAssertEqual(sfDefaults.photometricInterpretation, "MONOCHROME2")

        // Multi-frame single bit
        let sbDefaults = SecondaryCaptureType.multiframeSingleBit.defaultPixelCharacteristics
        XCTAssertEqual(sbDefaults.samplesPerPixel, 1)
        XCTAssertEqual(sbDefaults.bitsAllocated, 1)

        // Multi-frame grayscale word - 16 bit
        let gwDefaults = SecondaryCaptureType.multiframeGrayscaleWord.defaultPixelCharacteristics
        XCTAssertEqual(gwDefaults.bitsAllocated, 16)
        XCTAssertEqual(gwDefaults.bitsStored, 16)
        XCTAssertEqual(gwDefaults.highBit, 15)

        // Multi-frame true color - RGB
        let tcDefaults = SecondaryCaptureType.multiframeTrueColor.defaultPixelCharacteristics
        XCTAssertEqual(tcDefaults.samplesPerPixel, 3)
        XCTAssertEqual(tcDefaults.photometricInterpretation, "RGB")
    }

    // MARK: - ConversionType Tests

    func test_conversionType_allTypes() {
        XCTAssertEqual(ConversionType.digitizedVideo.rawValue, "DV")
        XCTAssertEqual(ConversionType.digitalInterface.rawValue, "DI")
        XCTAssertEqual(ConversionType.digitizedFilm.rawValue, "DF")
        XCTAssertEqual(ConversionType.workstation.rawValue, "WSD")
        XCTAssertEqual(ConversionType.scannedDocument.rawValue, "SD")
        XCTAssertEqual(ConversionType.scannedImage.rawValue, "SI")
        XCTAssertEqual(ConversionType.drawing.rawValue, "DRW")
        XCTAssertEqual(ConversionType.synthesized.rawValue, "SYN")
    }

    /// PS3.3 2026a Table C.8-24, Conversion Type (0008,0064) Defined Terms.
    func test_conversionType_definedTerms_matchTableC8_24() {
        XCTAssertEqual(ConversionType.definedTerms, ["DV", "DI", "DF", "WSD", "SD", "SI", "DRW", "SYN"])
        XCTAssertEqual(ConversionType.allCases.map(\.rawValue), ConversionType.definedTerms)
        for term in ConversionType.definedTerms {
            let parsed = ConversionType(definedTerm: term)
            XCTAssertEqual(parsed?.rawValue, term)
            XCTAssertEqual(parsed?.standardTerm, term)
            XCTAssertEqual(parsed?.isDefinedTerm, true)
        }
        XCTAssertNil(ConversionType(definedTerm: ""))
        XCTAssertNil(ConversionType(definedTerm: "BOGUS"))
    }

    /// Conversion Type is Type 1: the deprecated empty case is never written; it maps to WSD.
    @available(*, deprecated)
    func test_conversionType_unknown_isNotWritten_mapsToWSD() throws {
        XCTAssertEqual(ConversionType.unknown.rawValue, "")
        XCTAssertEqual(ConversionType.unknown.standardTerm, "WSD")
        XCTAssertFalse(ConversionType.unknown.isDefinedTerm)
        XCTAssertFalse(ConversionType.allCases.contains(.unknown))

        let dataSet = try SecondaryCaptureBuilder(
            secondaryCaptureType: .singleFrame, rows: 4, columns: 4,
            studyInstanceUID: "1.2.3.4.5", seriesInstanceUID: "1.2.3.4.5.6"
        )
        .setConversionType(.unknown)
        .buildDataSet()
        XCTAssertEqual(dataSet.string(for: .conversionType), "WSD")
    }

    func test_conversionType_fromDICOMValue() {
        XCTAssertEqual(ConversionType(dicomValue: "DV"), .digitizedVideo)
        XCTAssertEqual(ConversionType(dicomValue: "DI"), .digitalInterface)
        XCTAssertEqual(ConversionType(dicomValue: "DF"), .digitizedFilm)
        XCTAssertEqual(ConversionType(dicomValue: "WSD"), .workstation)
        XCTAssertEqual(ConversionType(dicomValue: "SD"), .scannedDocument)
        XCTAssertEqual(ConversionType(dicomValue: "SI"), .scannedImage)
        XCTAssertEqual(ConversionType(dicomValue: "DRW"), .drawing)
        XCTAssertEqual(ConversionType(dicomValue: "SYN"), .synthesized)
        // Parser tolerance: a value outside Table C.8-24 is kept as a non-term.
        XCTAssertFalse(ConversionType(dicomValue: "UNKNOWN").isDefinedTerm)
        XCTAssertFalse(ConversionType(dicomValue: "").isDefinedTerm)
        XCTAssertEqual(ConversionType(dicomValue: "UNKNOWN").standardTerm, "WSD")
    }

    func test_conversionType_fromDICOMValue_withWhitespace() {
        XCTAssertEqual(ConversionType(dicomValue: "  DV  "), .digitizedVideo)
        XCTAssertEqual(ConversionType(dicomValue: " WSD "), .workstation)
    }

    func test_conversionType_displayName() {
        XCTAssertEqual(ConversionType.digitizedVideo.displayName, "Digitized Video")
        XCTAssertEqual(ConversionType.digitalInterface.displayName, "Digital Interface")
        XCTAssertEqual(ConversionType.digitizedFilm.displayName, "Digitized Film")
        XCTAssertEqual(ConversionType.workstation.displayName, "Workstation")
        XCTAssertEqual(ConversionType.scannedDocument.displayName, "Scanned Document")
        XCTAssertEqual(ConversionType.scannedImage.displayName, "Scanned Image")
        XCTAssertEqual(ConversionType.drawing.displayName, "Drawing")
        XCTAssertEqual(ConversionType.synthesized.displayName, "Synthetic Image")
        XCTAssertEqual(ConversionType(dicomValue: "BOGUS").displayName, "Unknown")
    }

    // MARK: - SOP Class UID Constants

    func test_sopClassUIDs() {
        XCTAssertEqual(SecondaryCaptureImage.secondaryCaptureImageStorageUID, "1.2.840.10008.5.1.4.1.1.7")
        XCTAssertEqual(SecondaryCaptureImage.multiframeSingleBitSCImageStorageUID, "1.2.840.10008.5.1.4.1.1.7.1")
        XCTAssertEqual(SecondaryCaptureImage.multiframeGrayscaleByteSCImageStorageUID, "1.2.840.10008.5.1.4.1.1.7.2")
        XCTAssertEqual(SecondaryCaptureImage.multiframeGrayscaleWordSCImageStorageUID, "1.2.840.10008.5.1.4.1.1.7.3")
        XCTAssertEqual(SecondaryCaptureImage.multiframeTrueColorSCImageStorageUID, "1.2.840.10008.5.1.4.1.1.7.4")
    }

    // MARK: - SecondaryCaptureImage Property Tests

    func test_secondaryCaptureImage_singleFrame_properties() {
        let sc = SecondaryCaptureImage(
            sopInstanceUID: "1.2.3.4.5",
            sopClassUID: SecondaryCaptureImage.secondaryCaptureImageStorageUID,
            studyInstanceUID: "1.2.3.4",
            seriesInstanceUID: "1.2.3.4.6",
            rows: 512,
            columns: 512
        )
        XCTAssertEqual(sc.secondaryCaptureType, .singleFrame)
        XCTAssertTrue(sc.isSingleFrame)
        XCTAssertFalse(sc.isMultiFrame)
        XCTAssertEqual(sc.resolution, "512x512")
        XCTAssertTrue(sc.isMonochrome)
        XCTAssertFalse(sc.isColor)
    }

    func test_secondaryCaptureImage_multiFrame_properties() {
        let sc = SecondaryCaptureImage(
            sopInstanceUID: "1.2.3.4.5",
            sopClassUID: SecondaryCaptureImage.multiframeTrueColorSCImageStorageUID,
            studyInstanceUID: "1.2.3.4",
            seriesInstanceUID: "1.2.3.4.6",
            rows: 1024,
            columns: 768,
            numberOfFrames: 5,
            samplesPerPixel: 3,
            photometricInterpretation: "RGB"
        )
        XCTAssertEqual(sc.secondaryCaptureType, .multiframeTrueColor)
        XCTAssertFalse(sc.isSingleFrame)
        XCTAssertTrue(sc.isMultiFrame)
        XCTAssertEqual(sc.resolution, "768x1024")
        XCTAssertFalse(sc.isMonochrome)
        XCTAssertTrue(sc.isColor)
        XCTAssertEqual(sc.numberOfFrames, 5)
    }

    func test_secondaryCaptureImage_withMetadata() {
        let sc = SecondaryCaptureImage(
            sopInstanceUID: "1.2.3.4.5",
            sopClassUID: SecondaryCaptureImage.secondaryCaptureImageStorageUID,
            studyInstanceUID: "1.2.3.4",
            seriesInstanceUID: "1.2.3.4.6",
            patientName: "Doe^John",
            patientID: "12345",
            modality: "OT",
            seriesDescription: "Clinical Photo",
            conversionType: .workstation,
            rows: 256,
            columns: 256,
            imageType: ["DERIVED", "SECONDARY"]
        )
        XCTAssertEqual(sc.patientName, "Doe^John")
        XCTAssertEqual(sc.patientID, "12345")
        XCTAssertEqual(sc.modality, "OT")
        XCTAssertEqual(sc.seriesDescription, "Clinical Photo")
        let expectedConversionType: ConversionType = .workstation
        XCTAssertEqual(sc.conversionType, expectedConversionType)
        XCTAssertEqual(sc.imageType, ["DERIVED", "SECONDARY"])
    }

    // MARK: - SecondaryCaptureBuilder Tests

    func test_builder_singleFrame_grayscale() throws {
        let pixelData = Data(repeating: 128, count: 256 * 256)
        let sc = try SecondaryCaptureBuilder(
            secondaryCaptureType: .singleFrame,
            rows: 256,
            columns: 256,
            studyInstanceUID: "1.2.3.4.5",
            seriesInstanceUID: "1.2.3.4.5.6"
        )
        .setConversionType(.workstation)
        .setPatientName("Smith^John")
        .setPatientID("12345")
        .setPixelData(pixelData)
        .build()

        XCTAssertEqual(sc.sopClassUID, SecondaryCaptureImage.secondaryCaptureImageStorageUID)
        XCTAssertEqual(sc.rows, 256)
        XCTAssertEqual(sc.columns, 256)
        XCTAssertEqual(sc.conversionType, .workstation)
        XCTAssertEqual(sc.patientName, "Smith^John")
        XCTAssertEqual(sc.patientID, "12345")
        XCTAssertEqual(sc.samplesPerPixel, 1)
        XCTAssertEqual(sc.photometricInterpretation, "MONOCHROME2")
        XCTAssertEqual(sc.bitsAllocated, 8)
        XCTAssertEqual(sc.bitsStored, 8)
        XCTAssertEqual(sc.highBit, 7)
        XCTAssertNotNil(sc.pixelData)
        XCTAssertEqual(sc.pixelData?.count, 256 * 256)
        XCTAssertFalse(sc.sopInstanceUID.isEmpty)
        XCTAssertEqual(sc.modality, "OT")
        XCTAssertEqual(sc.imageType, ["DERIVED", "SECONDARY"])
    }

    func test_builder_multiframeTrueColor() throws {
        let pixelData = Data(repeating: 0, count: 128 * 128 * 3 * 5)
        let sc = try SecondaryCaptureBuilder(
            secondaryCaptureType: .multiframeTrueColor,
            rows: 128,
            columns: 128,
            studyInstanceUID: "1.2.3.4.5",
            seriesInstanceUID: "1.2.3.4.5.6"
        )
        .setNumberOfFrames(5)
        .setConversionType(.digitizedVideo)
        .setPixelData(pixelData)
        .build()

        XCTAssertEqual(sc.sopClassUID, SecondaryCaptureImage.multiframeTrueColorSCImageStorageUID)
        XCTAssertEqual(sc.numberOfFrames, 5)
        XCTAssertEqual(sc.samplesPerPixel, 3)
        XCTAssertEqual(sc.photometricInterpretation, "RGB")
        XCTAssertEqual(sc.bitsAllocated, 8)
        XCTAssertEqual(sc.conversionType, .digitizedVideo)
    }

    func test_builder_multiframeGrayscaleWord() throws {
        let sc = try SecondaryCaptureBuilder(
            secondaryCaptureType: .multiframeGrayscaleWord,
            rows: 64,
            columns: 64,
            studyInstanceUID: "1.2.3.4.5",
            seriesInstanceUID: "1.2.3.4.5.6"
        )
        .setNumberOfFrames(3)
        .build()

        XCTAssertEqual(sc.sopClassUID, SecondaryCaptureImage.multiframeGrayscaleWordSCImageStorageUID)
        XCTAssertEqual(sc.bitsAllocated, 16)
        XCTAssertEqual(sc.bitsStored, 16)
        XCTAssertEqual(sc.highBit, 15)
        XCTAssertEqual(sc.samplesPerPixel, 1)
    }

    func test_builder_multiframeSingleBit() throws {
        let sc = try SecondaryCaptureBuilder(
            secondaryCaptureType: .multiframeSingleBit,
            rows: 100,
            columns: 100,
            studyInstanceUID: "1.2.3.4.5",
            seriesInstanceUID: "1.2.3.4.5.6"
        )
        .setNumberOfFrames(2)
        .build()

        XCTAssertEqual(sc.sopClassUID, SecondaryCaptureImage.multiframeSingleBitSCImageStorageUID)
        XCTAssertEqual(sc.bitsAllocated, 1)
        XCTAssertEqual(sc.bitsStored, 1)
        XCTAssertEqual(sc.highBit, 0)
    }

    func test_builder_multiframeGrayscaleByte() throws {
        let sc = try SecondaryCaptureBuilder(
            secondaryCaptureType: .multiframeGrayscaleByte,
            rows: 200,
            columns: 200,
            studyInstanceUID: "1.2.3.4.5",
            seriesInstanceUID: "1.2.3.4.5.6"
        )
        .setNumberOfFrames(4)
        .build()

        XCTAssertEqual(sc.sopClassUID, SecondaryCaptureImage.multiframeGrayscaleByteSCImageStorageUID)
        XCTAssertEqual(sc.bitsAllocated, 8)
        XCTAssertEqual(sc.bitsStored, 8)
        XCTAssertEqual(sc.highBit, 7)
        XCTAssertEqual(sc.samplesPerPixel, 1)
        XCTAssertEqual(sc.photometricInterpretation, "MONOCHROME2")
    }

    func test_builder_withAllMetadata() throws {
        let sc = try SecondaryCaptureBuilder(
            secondaryCaptureType: .singleFrame,
            rows: 512,
            columns: 512,
            studyInstanceUID: "1.2.3.4.5",
            seriesInstanceUID: "1.2.3.4.5.6"
        )
        .setSOPInstanceUID("1.2.3.4.5.7")
        .setInstanceNumber(1)
        .setPatientName("Doe^Jane")
        .setPatientID("54321")
        .setModality("OT")
        .setSeriesDescription("Screen Capture")
        .setSeriesNumber(1)
        .setConversionType(.workstation)
        .setImageType(["ORIGINAL", "PRIMARY"])
        .setDerivationDescription("Screen capture from PACS workstation")
        .setBurnedInAnnotation("YES")
        .build()

        XCTAssertEqual(sc.sopInstanceUID, "1.2.3.4.5.7")
        XCTAssertEqual(sc.instanceNumber, 1)
        XCTAssertEqual(sc.patientName, "Doe^Jane")
        XCTAssertEqual(sc.patientID, "54321")
        XCTAssertEqual(sc.modality, "OT")
        XCTAssertEqual(sc.seriesDescription, "Screen Capture")
        XCTAssertEqual(sc.seriesNumber, 1)
        XCTAssertEqual(sc.conversionType, .workstation)
        XCTAssertEqual(sc.imageType, ["ORIGINAL", "PRIMARY"])
        XCTAssertEqual(sc.derivationDescription, "Screen capture from PACS workstation")
        XCTAssertEqual(sc.burnedInAnnotation, "YES")
    }

    func test_builder_withCustomPixelCharacteristics() throws {
        let sc = try SecondaryCaptureBuilder(
            secondaryCaptureType: .singleFrame,
            rows: 256,
            columns: 256,
            studyInstanceUID: "1.2.3.4.5",
            seriesInstanceUID: "1.2.3.4.5.6"
        )
        .setSamplesPerPixel(3)
        .setPhotometricInterpretation("RGB")
        .setBitDepth(allocated: 8, stored: 8, highBit: 7)
        .setPlanarConfiguration(0)
        .build()

        XCTAssertEqual(sc.samplesPerPixel, 3)
        XCTAssertEqual(sc.photometricInterpretation, "RGB")
        XCTAssertEqual(sc.bitsAllocated, 8)
        XCTAssertEqual(sc.planarConfiguration, 0)
    }

    // MARK: - Builder Validation Tests

    func test_builder_invalidRows_throws() {
        let builder = SecondaryCaptureBuilder(
            secondaryCaptureType: .singleFrame,
            rows: 0,
            columns: 256,
            studyInstanceUID: "1.2.3.4.5",
            seriesInstanceUID: "1.2.3.4.5.6"
        )

        XCTAssertThrowsError(try builder.build()) { error in
            XCTAssertTrue("\(error)".contains("Rows must be greater than 0"))
        }
    }

    func test_builder_invalidColumns_throws() {
        let builder = SecondaryCaptureBuilder(
            secondaryCaptureType: .singleFrame,
            rows: 256,
            columns: 0,
            studyInstanceUID: "1.2.3.4.5",
            seriesInstanceUID: "1.2.3.4.5.6"
        )

        XCTAssertThrowsError(try builder.build()) { error in
            XCTAssertTrue("\(error)".contains("Columns must be greater than 0"))
        }
    }

    func test_builder_unknownType_throws() {
        let builder = SecondaryCaptureBuilder(
            secondaryCaptureType: .unknown,
            rows: 256,
            columns: 256,
            studyInstanceUID: "1.2.3.4.5",
            seriesInstanceUID: "1.2.3.4.5.6"
        )

        XCTAssertThrowsError(try builder.build()) { error in
            XCTAssertTrue("\(error)".contains("Secondary Capture type cannot be unknown"))
        }
    }

    // MARK: - DataSet Conversion Tests

    func test_builder_buildDataSet_singleFrame() throws {
        let pixelData = Data(repeating: 200, count: 64 * 64)
        let dataSet = try SecondaryCaptureBuilder(
            secondaryCaptureType: .singleFrame,
            rows: 64,
            columns: 64,
            studyInstanceUID: "1.2.3.4.5",
            seriesInstanceUID: "1.2.3.4.5.6"
        )
        .setPatientName("Test^Patient")
        .setPatientID("TEST001")
        .setConversionType(.scannedImage)
        .setPixelData(pixelData)
        .buildDataSet()

        XCTAssertEqual(dataSet.string(for: .sopClassUID), SecondaryCaptureImage.secondaryCaptureImageStorageUID)
        XCTAssertNotNil(dataSet.string(for: .sopInstanceUID))
        XCTAssertEqual(dataSet.string(for: .studyInstanceUID), "1.2.3.4.5")
        XCTAssertEqual(dataSet.string(for: .seriesInstanceUID), "1.2.3.4.5.6")
        XCTAssertEqual(dataSet.string(for: .patientName), "Test^Patient")
        XCTAssertEqual(dataSet.string(for: .patientID), "TEST001")
        XCTAssertEqual(dataSet.string(for: .conversionType), "SI")
        XCTAssertEqual(dataSet[.rows]?.uint16Value, 64)
        XCTAssertEqual(dataSet[.columns]?.uint16Value, 64)
        XCTAssertEqual(dataSet[.samplesPerPixel]?.uint16Value, 1)
        XCTAssertEqual(dataSet.string(for: .photometricInterpretation), "MONOCHROME2")
        XCTAssertNotNil(dataSet[.pixelData])
    }

    func test_builder_buildDataSet_multiframe() throws {
        let dataSet = try SecondaryCaptureBuilder(
            secondaryCaptureType: .multiframeTrueColor,
            rows: 128,
            columns: 128,
            studyInstanceUID: "1.2.3.4.5",
            seriesInstanceUID: "1.2.3.4.5.6"
        )
        .setNumberOfFrames(3)
        .buildDataSet()

        XCTAssertEqual(dataSet.string(for: .sopClassUID), SecondaryCaptureImage.multiframeTrueColorSCImageStorageUID)
        XCTAssertEqual(dataSet[.samplesPerPixel]?.uint16Value, 3)
        XCTAssertEqual(dataSet.string(for: .photometricInterpretation), "RGB")
        // Should include numberOfFrames for multi-frame types
        XCTAssertNotNil(dataSet[.numberOfFrames])
    }

    func test_toDataSet_includesImageType() throws {
        let sc = try SecondaryCaptureBuilder(
            secondaryCaptureType: .singleFrame,
            rows: 64,
            columns: 64,
            studyInstanceUID: "1.2.3.4.5",
            seriesInstanceUID: "1.2.3.4.5.6"
        )
        .setImageType(["DERIVED", "SECONDARY", "CAPTURE"])
        .build()

        let dataSet = sc.toDataSet()
        let imageTypeStr = dataSet.string(for: .imageType)
        XCTAssertEqual(imageTypeStr, "DERIVED\\SECONDARY\\CAPTURE")
    }

    func test_toDataSet_includesSCFields() throws {
        let sc = try SecondaryCaptureBuilder(
            secondaryCaptureType: .singleFrame,
            rows: 64,
            columns: 64,
            studyInstanceUID: "1.2.3.4.5",
            seriesInstanceUID: "1.2.3.4.5.6"
        )
        .setConversionType(.synthesized)
        .setBurnedInAnnotation("NO")
        .setDerivationDescription("AI-generated synthetic image")
        .build()

        let dataSet = sc.toDataSet()
        XCTAssertEqual(dataSet.string(for: .conversionType), "SYN")
        XCTAssertEqual(dataSet.string(for: .burnedInAnnotation), "NO")
        XCTAssertEqual(dataSet.string(for: .derivationDescription), "AI-generated synthetic image")
    }

    // MARK: - Parser Tests

    func test_parser_basicParsing() throws {
        var dataSet = DataSet()
        dataSet.setString("1.2.3.4.5.6.7", for: .sopInstanceUID, vr: .UI)
        dataSet.setString(SecondaryCaptureImage.secondaryCaptureImageStorageUID, for: .sopClassUID, vr: .UI)
        dataSet.setString("1.2.3.4.5", for: .studyInstanceUID, vr: .UI)
        dataSet.setString("1.2.3.4.5.6", for: .seriesInstanceUID, vr: .UI)
        dataSet[.rows] = DataElement.uint16(tag: .rows, value: 512)
        dataSet[.columns] = DataElement.uint16(tag: .columns, value: 512)
        dataSet[.samplesPerPixel] = DataElement.uint16(tag: .samplesPerPixel, value: 1)
        dataSet.setString("MONOCHROME2", for: .photometricInterpretation, vr: .CS)
        dataSet[.bitsAllocated] = DataElement.uint16(tag: .bitsAllocated, value: 8)
        dataSet[.bitsStored] = DataElement.uint16(tag: .bitsStored, value: 8)
        dataSet[.highBit] = DataElement.uint16(tag: .highBit, value: 7)
        dataSet[.pixelRepresentation] = DataElement.uint16(tag: .pixelRepresentation, value: 0)
        dataSet.setString("WSD", for: .conversionType, vr: .CS)

        let sc = try SecondaryCaptureParser.parse(from: dataSet)
        XCTAssertEqual(sc.sopInstanceUID, "1.2.3.4.5.6.7")
        XCTAssertEqual(sc.sopClassUID, SecondaryCaptureImage.secondaryCaptureImageStorageUID)
        XCTAssertEqual(sc.rows, 512)
        XCTAssertEqual(sc.columns, 512)
        XCTAssertEqual(sc.conversionType, .workstation)
        XCTAssertEqual(sc.samplesPerPixel, 1)
        XCTAssertEqual(sc.photometricInterpretation, "MONOCHROME2")
        XCTAssertEqual(sc.numberOfFrames, 1)
    }

    func test_parser_withPatientInfo() throws {
        var dataSet = DataSet()
        dataSet.setString("1.2.3.4.5.6.7", for: .sopInstanceUID, vr: .UI)
        dataSet.setString(SecondaryCaptureImage.secondaryCaptureImageStorageUID, for: .sopClassUID, vr: .UI)
        dataSet.setString("1.2.3.4.5", for: .studyInstanceUID, vr: .UI)
        dataSet.setString("1.2.3.4.5.6", for: .seriesInstanceUID, vr: .UI)
        dataSet[.rows] = DataElement.uint16(tag: .rows, value: 256)
        dataSet[.columns] = DataElement.uint16(tag: .columns, value: 256)
        dataSet.setString("Smith^Jane", for: .patientName, vr: .PN)
        dataSet.setString("98765", for: .patientID, vr: .LO)
        dataSet.setString("OT", for: .modality, vr: .CS)
        dataSet.setString("Diagnostic Photo", for: .seriesDescription, vr: .LO)

        let sc = try SecondaryCaptureParser.parse(from: dataSet)
        XCTAssertEqual(sc.patientName, "Smith^Jane")
        XCTAssertEqual(sc.patientID, "98765")
        XCTAssertEqual(sc.modality, "OT")
        XCTAssertEqual(sc.seriesDescription, "Diagnostic Photo")
    }

    func test_parser_withImageType() throws {
        var dataSet = DataSet()
        dataSet.setString("1.2.3.4.5.6.7", for: .sopInstanceUID, vr: .UI)
        dataSet.setString(SecondaryCaptureImage.secondaryCaptureImageStorageUID, for: .sopClassUID, vr: .UI)
        dataSet.setString("1.2.3.4.5", for: .studyInstanceUID, vr: .UI)
        dataSet.setString("1.2.3.4.5.6", for: .seriesInstanceUID, vr: .UI)
        dataSet[.rows] = DataElement.uint16(tag: .rows, value: 128)
        dataSet[.columns] = DataElement.uint16(tag: .columns, value: 128)
        dataSet.setString("DERIVED\\SECONDARY", for: .imageType, vr: .CS)
        dataSet.setString("YES", for: .burnedInAnnotation, vr: .CS)

        let sc = try SecondaryCaptureParser.parse(from: dataSet)
        XCTAssertEqual(sc.imageType, ["DERIVED", "SECONDARY"])
        XCTAssertEqual(sc.burnedInAnnotation, "YES")
    }

    func test_parser_multiframe() throws {
        var dataSet = DataSet()
        dataSet.setString("1.2.3.4.5.6.7", for: .sopInstanceUID, vr: .UI)
        dataSet.setString(SecondaryCaptureImage.multiframeTrueColorSCImageStorageUID, for: .sopClassUID, vr: .UI)
        dataSet.setString("1.2.3.4.5", for: .studyInstanceUID, vr: .UI)
        dataSet.setString("1.2.3.4.5.6", for: .seriesInstanceUID, vr: .UI)
        dataSet[.rows] = DataElement.uint16(tag: .rows, value: 320)
        dataSet[.columns] = DataElement.uint16(tag: .columns, value: 240)
        dataSet[.samplesPerPixel] = DataElement.uint16(tag: .samplesPerPixel, value: 3)
        dataSet.setString("RGB", for: .photometricInterpretation, vr: .CS)
        dataSet.setString("10", for: .numberOfFrames, vr: .IS)

        let sc = try SecondaryCaptureParser.parse(from: dataSet)
        XCTAssertEqual(sc.secondaryCaptureType, .multiframeTrueColor)
        XCTAssertEqual(sc.numberOfFrames, 10)
        XCTAssertEqual(sc.samplesPerPixel, 3)
        XCTAssertEqual(sc.photometricInterpretation, "RGB")
    }

    // MARK: - Parser Error Tests

    func test_parser_missingSOPInstanceUID_throws() {
        var dataSet = DataSet()
        dataSet.setString("1.2.3.4.5", for: .studyInstanceUID, vr: .UI)
        dataSet.setString("1.2.3.4.5.6", for: .seriesInstanceUID, vr: .UI)
        dataSet[.rows] = DataElement.uint16(tag: .rows, value: 256)
        dataSet[.columns] = DataElement.uint16(tag: .columns, value: 256)

        XCTAssertThrowsError(try SecondaryCaptureParser.parse(from: dataSet)) { error in
            XCTAssertTrue("\(error)".contains("Missing SOP Instance UID"))
        }
    }

    func test_parser_missingStudyInstanceUID_throws() {
        var dataSet = DataSet()
        dataSet.setString("1.2.3.4.5.6.7", for: .sopInstanceUID, vr: .UI)
        dataSet.setString("1.2.3.4.5.6", for: .seriesInstanceUID, vr: .UI)
        dataSet[.rows] = DataElement.uint16(tag: .rows, value: 256)
        dataSet[.columns] = DataElement.uint16(tag: .columns, value: 256)

        XCTAssertThrowsError(try SecondaryCaptureParser.parse(from: dataSet)) { error in
            XCTAssertTrue("\(error)".contains("Missing Study Instance UID"))
        }
    }

    func test_parser_missingSeriesInstanceUID_throws() {
        var dataSet = DataSet()
        dataSet.setString("1.2.3.4.5.6.7", for: .sopInstanceUID, vr: .UI)
        dataSet.setString("1.2.3.4.5", for: .studyInstanceUID, vr: .UI)
        dataSet[.rows] = DataElement.uint16(tag: .rows, value: 256)
        dataSet[.columns] = DataElement.uint16(tag: .columns, value: 256)

        XCTAssertThrowsError(try SecondaryCaptureParser.parse(from: dataSet)) { error in
            XCTAssertTrue("\(error)".contains("Missing Series Instance UID"))
        }
    }

    func test_parser_missingRows_throws() {
        var dataSet = DataSet()
        dataSet.setString("1.2.3.4.5.6.7", for: .sopInstanceUID, vr: .UI)
        dataSet.setString("1.2.3.4.5", for: .studyInstanceUID, vr: .UI)
        dataSet.setString("1.2.3.4.5.6", for: .seriesInstanceUID, vr: .UI)
        dataSet[.columns] = DataElement.uint16(tag: .columns, value: 256)

        XCTAssertThrowsError(try SecondaryCaptureParser.parse(from: dataSet)) { error in
            XCTAssertTrue("\(error)".contains("Missing Rows attribute"))
        }
    }

    func test_parser_missingColumns_throws() {
        var dataSet = DataSet()
        dataSet.setString("1.2.3.4.5.6.7", for: .sopInstanceUID, vr: .UI)
        dataSet.setString("1.2.3.4.5", for: .studyInstanceUID, vr: .UI)
        dataSet.setString("1.2.3.4.5.6", for: .seriesInstanceUID, vr: .UI)
        dataSet[.rows] = DataElement.uint16(tag: .rows, value: 256)

        XCTAssertThrowsError(try SecondaryCaptureParser.parse(from: dataSet)) { error in
            XCTAssertTrue("\(error)".contains("Missing Columns attribute"))
        }
    }

    // MARK: - Round-Trip Tests

    func test_roundTrip_singleFrame() throws {
        let originalSC = try SecondaryCaptureBuilder(
            secondaryCaptureType: .singleFrame,
            rows: 256,
            columns: 256,
            studyInstanceUID: "1.2.3.4.5",
            seriesInstanceUID: "1.2.3.4.5.6"
        )
        .setSOPInstanceUID("1.2.3.4.5.7")
        .setConversionType(.workstation)
        .setPatientName("Test^Patient")
        .setPatientID("TEST001")
        .setModality("OT")
        .setSeriesDescription("Screen Capture")
        .setImageType(["DERIVED", "SECONDARY"])
        .setBurnedInAnnotation("NO")
        .build()

        // Convert to DataSet
        let dataSet = originalSC.toDataSet()

        // Parse back
        let parsedSC = try SecondaryCaptureParser.parse(from: dataSet)

        // Verify round-trip
        XCTAssertEqual(parsedSC.sopInstanceUID, originalSC.sopInstanceUID)
        XCTAssertEqual(parsedSC.sopClassUID, originalSC.sopClassUID)
        XCTAssertEqual(parsedSC.studyInstanceUID, originalSC.studyInstanceUID)
        XCTAssertEqual(parsedSC.seriesInstanceUID, originalSC.seriesInstanceUID)
        XCTAssertEqual(parsedSC.rows, originalSC.rows)
        XCTAssertEqual(parsedSC.columns, originalSC.columns)
        XCTAssertEqual(parsedSC.conversionType, originalSC.conversionType)
        XCTAssertEqual(parsedSC.patientName, originalSC.patientName)
        XCTAssertEqual(parsedSC.patientID, originalSC.patientID)
        XCTAssertEqual(parsedSC.modality, originalSC.modality)
        XCTAssertEqual(parsedSC.seriesDescription, originalSC.seriesDescription)
        XCTAssertEqual(parsedSC.imageType, originalSC.imageType)
        XCTAssertEqual(parsedSC.burnedInAnnotation, originalSC.burnedInAnnotation)
    }

    func test_roundTrip_multiframeTrueColor() throws {
        let pixelData = Data(repeating: 100, count: 64 * 64 * 3 * 3)
        let originalSC = try SecondaryCaptureBuilder(
            secondaryCaptureType: .multiframeTrueColor,
            rows: 64,
            columns: 64,
            studyInstanceUID: "1.2.3.4.5",
            seriesInstanceUID: "1.2.3.4.5.6"
        )
        .setSOPInstanceUID("1.2.3.4.5.8")
        .setNumberOfFrames(3)
        .setConversionType(.digitizedVideo)
        .setPixelData(pixelData)
        .build()

        let dataSet = originalSC.toDataSet()
        let parsedSC = try SecondaryCaptureParser.parse(from: dataSet)

        XCTAssertEqual(parsedSC.sopClassUID, SecondaryCaptureImage.multiframeTrueColorSCImageStorageUID)
        XCTAssertEqual(parsedSC.numberOfFrames, 3)
        XCTAssertEqual(parsedSC.samplesPerPixel, 3)
        XCTAssertEqual(parsedSC.photometricInterpretation, "RGB")
        XCTAssertEqual(parsedSC.pixelData?.count, pixelData.count)
    }

    // MARK: - Tag Tests

    func test_secondaryCaptureTag_conversionType() {
        XCTAssertEqual(Tag.conversionType.group, 0x0008)
        XCTAssertEqual(Tag.conversionType.element, 0x0064)
    }

    func test_secondaryCaptureTag_dateOfSecondaryCapture() {
        XCTAssertEqual(Tag.dateOfSecondaryCapture.group, 0x0018)
        XCTAssertEqual(Tag.dateOfSecondaryCapture.element, 0x1012)
    }

    func test_secondaryCaptureTag_timeOfSecondaryCapture() {
        XCTAssertEqual(Tag.timeOfSecondaryCapture.group, 0x0018)
        XCTAssertEqual(Tag.timeOfSecondaryCapture.element, 0x1014)
    }

    func test_secondaryCaptureTag_pageNumberVector() {
        XCTAssertEqual(Tag.pageNumberVector.group, 0x0018)
        XCTAssertEqual(Tag.pageNumberVector.element, 0x2001)
    }

    // MARK: - IOD completeness (PS3.3 2026a Tables A.8-1 … A.8-5)

    /// Type 1 attributes of the mandatory modules shared by every SC IOD:
    /// SOP Common (C.12-1), General Study (C.7-3), General Series (C.7-5a),
    /// SC Equipment (C.8-24), Image Pixel (C.7-11a).
    private let commonType1: [Tag] = [
        .sopClassUID, .sopInstanceUID, .studyInstanceUID, .modality, .seriesInstanceUID,
        .conversionType, .samplesPerPixel, .photometricInterpretation, .rows, .columns,
        .bitsAllocated, .bitsStored, .highBit, .pixelRepresentation,
    ]

    /// Type 2 attributes: Patient (C.7-1), General Study (C.7-3), General Series
    /// (C.7-5a), General Image (C.7-9, Patient Orientation 2C always required for SC).
    private let commonType2: [Tag] = [
        .patientName, .patientID, .patientBirthDate, .patientSex,
        .studyDate, .studyTime, .referringPhysicianName, .studyID, .accessionNumber,
        .seriesNumber, .instanceNumber, .patientOrientation,
    ]

    private func assertType1Present(_ dataSet: DataSet, _ tags: [Tag], file: StaticString = #filePath, line: UInt = #line) {
        for tag in tags {
            guard let element = dataSet[tag] else {
                XCTFail("Type 1 \(tag) missing", file: file, line: line); continue
            }
            XCTAssertFalse(element.valueData.isEmpty, "Type 1 \(tag) is empty", file: file, line: line)
            if let text = element.stringValue {
                XCTAssertFalse(text.isEmpty, "Type 1 \(tag) is empty", file: file, line: line)
            }
        }
    }

    private func assertType2Present(_ dataSet: DataSet, _ tags: [Tag], file: StaticString = #filePath, line: UInt = #line) {
        for tag in tags {
            XCTAssertNotNil(dataSet[tag], "Type 2 \(tag) missing", file: file, line: line)
        }
    }

    private func frameIncrementTarget(_ dataSet: DataSet) -> Tag? {
        guard let element = dataSet[.frameIncrementPointer], element.vr == .AT, element.valueData.count == 4 else { return nil }
        let bytes = [UInt8](element.valueData)
        return Tag(group: UInt16(bytes[0]) | UInt16(bytes[1]) << 8, element: UInt16(bytes[2]) | UInt16(bytes[3]) << 8)
    }

    func test_iod_singleFrame_type1AndType2Complete() throws {
        let dataSet = try SecondaryCaptureBuilder(
            secondaryCaptureType: .singleFrame, rows: 4, columns: 4,
            studyInstanceUID: "1.2.3.4.5", seriesInstanceUID: "1.2.3.4.5.6"
        )
        .setPixelData(Data(repeating: 1, count: 16))
        .buildDataSet()

        assertType1Present(dataSet, commonType1 + [.pixelData])
        assertType2Present(dataSet, commonType2)
        XCTAssertEqual(dataSet.string(for: .conversionType), "WSD", "default Conversion Type")
        XCTAssertEqual(dataSet.string(for: .modality), "OT")
        XCTAssertEqual(dataSet.string(for: .patientName), "")
        XCTAssertEqual(dataSet.string(for: .patientOrientation), "")
        // The single-frame IOD (Table A.8-1) has no Multi-frame / SC Multi-frame modules.
        XCTAssertNil(dataSet[.numberOfFrames])
        XCTAssertNil(dataSet[.frameIncrementPointer])
        XCTAssertNil(dataSet[.presentationLUTShape])
        XCTAssertNil(dataSet[.burnedInAnnotation], "Burned In Annotation is Type 3 in Table C.7-9")
        XCTAssertNil(dataSet[.planarConfiguration], "Planar Configuration only when Samples per Pixel > 1")
        XCTAssertEqual(dataSet[.conversionType]?.vr, .CS)
        XCTAssertEqual(dataSet[.patientBirthDate]?.vr, .DA)
        XCTAssertEqual(dataSet[.patientSex]?.vr, .CS)
        XCTAssertEqual(dataSet[.referringPhysicianName]?.vr, .PN)
        XCTAssertEqual(dataSet[.studyID]?.vr, .SH)
        XCTAssertEqual(dataSet[.accessionNumber]?.vr, .SH)
        XCTAssertEqual(dataSet[.seriesNumber]?.vr, .IS)
        XCTAssertEqual(dataSet[.patientOrientation]?.vr, .CS)
    }

    func test_iod_singleFrame_type2ValuesRoundTrip() throws {
        let dataSet = try SecondaryCaptureBuilder(
            secondaryCaptureType: .singleFrame, rows: 4, columns: 4,
            studyInstanceUID: "1.2.3.4.5", seriesInstanceUID: "1.2.3.4.5.6"
        )
        .setPatientBirthDate(DICOMDate(year: 1980, month: 2, day: 29))
        .setPatientSex("F")
        .setStudyDateTime(date: DICOMDate(year: 2026, month: 9, day: 29), time: DICOMTime(hour: 10, minute: 5, second: 0))
        .setReferringPhysicianName("Ref^Doc")
        .setStudyID("S1")
        .setAccessionNumber("ACC1")
        .setSeriesNumber(7)
        .setInstanceNumber(3)
        .setPatientOrientation(row: "L", column: "P")
        .setStudyDescription("Desc")
        .buildDataSet()

        XCTAssertEqual(dataSet.string(for: .patientBirthDate), "19800229")
        XCTAssertEqual(dataSet.string(for: .patientSex), "F")
        XCTAssertEqual(dataSet.string(for: .studyDate), "20260929")
        XCTAssertEqual(dataSet.string(for: .studyTime), "100500")
        XCTAssertEqual(dataSet.string(for: .referringPhysicianName), "Ref^Doc")
        XCTAssertEqual(dataSet.string(for: .studyID), "S1")
        XCTAssertEqual(dataSet.string(for: .accessionNumber), "ACC1")
        XCTAssertEqual(dataSet.string(for: .seriesNumber), "7")
        XCTAssertEqual(dataSet.string(for: .instanceNumber), "3")
        XCTAssertEqual(dataSet.strings(for: .patientOrientation), ["L", "P"])
        XCTAssertEqual(dataSet.string(for: .studyDescription), "Desc")

        let parsed = try SecondaryCaptureParser.parse(from: dataSet)
        XCTAssertEqual(parsed.patientBirthDate?.dicomString, "19800229")
        XCTAssertEqual(parsed.patientSex, "F")
        XCTAssertEqual(parsed.studyDate?.dicomString, "20260929")
        XCTAssertEqual(parsed.referringPhysicianName, "Ref^Doc")
        XCTAssertEqual(parsed.studyID, "S1")
        XCTAssertEqual(parsed.accessionNumber, "ACC1")
        XCTAssertEqual(parsed.patientOrientation, ["L", "P"])
    }

    func test_iod_multiframeGrayscaleByte_type1Complete() throws {
        let dataSet = try SecondaryCaptureBuilder(
            secondaryCaptureType: .multiframeGrayscaleByte, rows: 4, columns: 4,
            studyInstanceUID: "1.2.3.4.5", seriesInstanceUID: "1.2.3.4.5.6"
        )
        .setNumberOfFrames(3)
        .setPixelData(Data(repeating: 1, count: 48))
        .buildDataSet()

        // Table A.8-3: Multi-frame (C.7-14), SC Multi-frame Image (C.8-25b), SC Multi-frame Vector (C.8-25c).
        assertType1Present(dataSet, commonType1 + [.pixelData, .numberOfFrames, .burnedInAnnotation, .frameIncrementPointer,
                                                    .presentationLUTShape, .rescaleIntercept, .rescaleSlope, .rescaleType])
        assertType2Present(dataSet, commonType2)
        XCTAssertEqual(dataSet.string(for: .numberOfFrames), "3")
        XCTAssertEqual(dataSet.string(for: .burnedInAnnotation), "NO")
        XCTAssertEqual(dataSet.string(for: .presentationLUTShape), "IDENTITY")
        // A.8.3.4: Rescale Intercept 0, Rescale Slope 1, Rescale Type US.
        XCTAssertEqual(dataSet.string(for: .rescaleIntercept), "0")
        XCTAssertEqual(dataSet.string(for: .rescaleSlope), "1")
        XCTAssertEqual(dataSet.string(for: .rescaleType), "US")
        XCTAssertEqual(dataSet[.rescaleIntercept]?.vr, .DS)
        XCTAssertEqual(dataSet[.rescaleType]?.vr, .LO)
        XCTAssertEqual(dataSet[.presentationLUTShape]?.vr, .CS)
        XCTAssertEqual(dataSet[.frameIncrementPointer]?.vr, .AT)
        XCTAssertEqual(frameIncrementTarget(dataSet), .pageNumberVector)
        XCTAssertEqual(dataSet.strings(for: .pageNumberVector), ["1", "2", "3"])
        XCTAssertNil(dataSet[.planarConfiguration], "A.8.3.4: Planar Configuration shall not be present")
    }

    func test_iod_multiframeGrayscaleWord_rescaleOverridable() throws {
        let dataSet = try SecondaryCaptureBuilder(
            secondaryCaptureType: .multiframeGrayscaleWord, rows: 4, columns: 4,
            studyInstanceUID: "1.2.3.4.5", seriesInstanceUID: "1.2.3.4.5.6"
        )
        .setNumberOfFrames(2)
        .setRescale(intercept: -1024, slope: 0.5, type: "HU")
        .setFrameTime(40)
        .setBurnedInAnnotation("YES")
        .setPixelData(Data(repeating: 1, count: 64))
        .buildDataSet()

        assertType1Present(dataSet, commonType1 + [.numberOfFrames, .burnedInAnnotation, .frameIncrementPointer,
                                                    .presentationLUTShape, .rescaleIntercept, .rescaleSlope, .rescaleType])
        XCTAssertEqual(dataSet.string(for: .rescaleIntercept), "-1024")
        XCTAssertEqual(dataSet.string(for: .rescaleSlope), "0.5")
        XCTAssertEqual(dataSet.string(for: .rescaleType), "HU")
        XCTAssertEqual(dataSet.string(for: .burnedInAnnotation), "YES")
        XCTAssertEqual(frameIncrementTarget(dataSet), .frameTime)
        XCTAssertEqual(dataSet.string(for: .frameTime), "40")
        XCTAssertNil(dataSet[.pageNumberVector])

        let parsed = try SecondaryCaptureParser.parse(from: dataSet)
        XCTAssertEqual(parsed.frameTime, 40)
        XCTAssertEqual(parsed.rescaleIntercept, -1024)
        XCTAssertEqual(parsed.rescaleSlope, 0.5)
        XCTAssertEqual(parsed.rescaleType, "HU")
    }

    func test_iod_multiframeSingleBit_noPresentationLUTShape() throws {
        let dataSet = try SecondaryCaptureBuilder(
            secondaryCaptureType: .multiframeSingleBit, rows: 8, columns: 8,
            studyInstanceUID: "1.2.3.4.5", seriesInstanceUID: "1.2.3.4.5.6"
        )
        .setNumberOfFrames(2)
        .setPageNumberVector([1, 2])
        .setPixelData(Data(repeating: 0xAA, count: 16))
        .buildDataSet()

        assertType1Present(dataSet, commonType1 + [.numberOfFrames, .burnedInAnnotation, .frameIncrementPointer])
        assertType2Present(dataSet, commonType2)
        // Table C.8-25b: the 1C condition (MONOCHROME2 and Bits Stored > 1) fails for 1 bit.
        XCTAssertNil(dataSet[.presentationLUTShape])
        XCTAssertNil(dataSet[.rescaleIntercept])
        XCTAssertNil(dataSet[.rescaleSlope])
        XCTAssertNil(dataSet[.rescaleType])
        XCTAssertNil(dataSet[.planarConfiguration])
        XCTAssertEqual(dataSet[.bitsAllocated]?.uint16Value, 1)
        XCTAssertEqual(frameIncrementTarget(dataSet), .pageNumberVector)
    }

    func test_iod_multiframeTrueColor_noGrayscaleAttributes_planarConfiguration0() throws {
        let dataSet = try SecondaryCaptureBuilder(
            secondaryCaptureType: .multiframeTrueColor, rows: 4, columns: 4,
            studyInstanceUID: "1.2.3.4.5", seriesInstanceUID: "1.2.3.4.5.6"
        )
        .setNumberOfFrames(2)
        .setFrameLabelVector(["a", "b"])
        .setPixelData(Data(repeating: 1, count: 96))
        .buildDataSet()

        assertType1Present(dataSet, commonType1 + [.numberOfFrames, .burnedInAnnotation, .frameIncrementPointer, .planarConfiguration])
        assertType2Present(dataSet, commonType2)
        XCTAssertNil(dataSet[.presentationLUTShape])
        XCTAssertNil(dataSet[.rescaleIntercept])
        XCTAssertEqual(dataSet[.planarConfiguration]?.uint16Value, 0, "A.8.5.4: 0 (color-by-pixel) for RGB")
        XCTAssertEqual(frameIncrementTarget(dataSet), .frameLabelVector)
        XCTAssertEqual(dataSet.strings(for: .frameLabelVector), ["a", "b"])
        XCTAssertEqual(dataSet[.frameLabelVector]?.vr, .SH)
    }

    func test_iod_multiframe_singleFrame_noFrameIncrementPointerRequired() throws {
        // Table C.8-25b specializes Frame Increment Pointer to "present if Number of Frames > 1".
        let dataSet = try SecondaryCaptureBuilder(
            secondaryCaptureType: .multiframeGrayscaleByte, rows: 4, columns: 4,
            studyInstanceUID: "1.2.3.4.5", seriesInstanceUID: "1.2.3.4.5.6"
        )
        .buildDataSet()
        XCTAssertEqual(dataSet.string(for: .numberOfFrames), "1")
        XCTAssertNil(dataSet[.frameIncrementPointer])
        XCTAssertNotNil(dataSet[.burnedInAnnotation])
    }

    func test_iod_multiframe_digitizedFilm_requiresNominalScannedPixelSpacing() throws {
        let builder = SecondaryCaptureBuilder(
            secondaryCaptureType: .multiframeGrayscaleByte, rows: 4, columns: 4,
            studyInstanceUID: "1.2.3.4.5", seriesInstanceUID: "1.2.3.4.5.6"
        )
        .setConversionType(.digitizedFilm)
        XCTAssertThrowsError(try builder.build()) { error in
            XCTAssertTrue("\(error)".contains("Nominal Scanned Pixel Spacing"))
        }

        let dataSet = try builder.setNominalScannedPixelSpacing(row: 0.1, column: 0.2).buildDataSet()
        XCTAssertEqual(dataSet.string(for: .conversionType), "DF")
        XCTAssertEqual(dataSet.strings(for: .nominalScannedPixelSpacing), ["0.1", "0.2"])
        XCTAssertEqual(dataSet[.nominalScannedPixelSpacing]?.vr, .DS)
        XCTAssertEqual(try SecondaryCaptureParser.parse(from: dataSet).nominalScannedPixelSpacing, [0.1, 0.2])
    }

    func test_iod_burnedInAnnotation_enumeratedValuesOnly() {
        let builder = SecondaryCaptureBuilder(
            secondaryCaptureType: .singleFrame, rows: 4, columns: 4,
            studyInstanceUID: "1.2.3.4.5", seriesInstanceUID: "1.2.3.4.5.6"
        )
        .setBurnedInAnnotation("MAYBE")
        XCTAssertThrowsError(try builder.build())
    }
}
