// NEMA-verified: 2026a, checked 2026-09-29 — SC attribute reads per PS3.3 2026a Tables C.7-1, C.7-3, C.7-5a, C.7-9, C.7-14, C.8-24, C.8-25, C.8-25b, C.8-25c
//
// SecondaryCaptureParser.swift
// DICOMKit
//
// Created by DICOMKit on 2026-02-09.
// Copyright © 2026 DICOMKit. All rights reserved.
//

import Foundation
import DICOMCore

/// Parser for DICOM Secondary Capture Image objects
///
/// Parses Secondary Capture IODs from DICOM data sets, extracting
/// image metadata and pixel data.
///
/// Reference: PS3.3 A.8 - Secondary Capture Image IOD
/// Reference: PS3.3 A.8.1 - Multi-frame SC Image IODs
public struct SecondaryCaptureParser {

    /// Parse a SecondaryCaptureImage from a DICOM data set
    ///
    /// - Parameter dataSet: DICOM data set containing a Secondary Capture IOD
    /// - Returns: Parsed SecondaryCaptureImage
    /// - Throws: DICOMError if parsing fails
    public static func parse(from dataSet: DataSet) throws -> SecondaryCaptureImage {
        // Parse SOP Instance UID (required)
        guard let sopInstanceUID = dataSet.string(for: .sopInstanceUID) else {
            throw DICOMError.parsingFailed("Missing SOP Instance UID")
        }

        let sopClassUID = dataSet.string(for: .sopClassUID) ?? SecondaryCaptureImage.secondaryCaptureImageStorageUID

        // Parse Study and Series UIDs (required)
        guard let studyInstanceUID = dataSet.string(for: .studyInstanceUID) else {
            throw DICOMError.parsingFailed("Missing Study Instance UID")
        }

        guard let seriesInstanceUID = dataSet.string(for: .seriesInstanceUID) else {
            throw DICOMError.parsingFailed("Missing Series Instance UID")
        }

        // Parse Image Pixel Module (required)
        guard let rowsValue = dataSet[.rows]?.uint16Value else {
            throw DICOMError.parsingFailed("Missing Rows attribute")
        }

        guard let columnsValue = dataSet[.columns]?.uint16Value else {
            throw DICOMError.parsingFailed("Missing Columns attribute")
        }

        // Parse Number of Frames (optional, defaults to 1)
        let numberOfFrames: Int
        if let nfElement = dataSet[.numberOfFrames]?.integerStringValue {
            numberOfFrames = nfElement.value
        } else {
            numberOfFrames = 1
        }

        // Parse Image Pixel Module optional attributes
        let samplesPerPixel = dataSet[.samplesPerPixel]?.uint16Value.flatMap { Int($0) } ?? 1
        let photometricInterpretation = dataSet.string(for: .photometricInterpretation) ?? "MONOCHROME2"
        let bitsAllocated = dataSet[.bitsAllocated]?.uint16Value.flatMap { Int($0) } ?? 8
        let bitsStored = dataSet[.bitsStored]?.uint16Value.flatMap { Int($0) } ?? 8
        let highBit = dataSet[.highBit]?.uint16Value.flatMap { Int($0) } ?? 7
        let pixelRepresentation = dataSet[.pixelRepresentation]?.uint16Value.flatMap { Int($0) } ?? 0
        let planarConfiguration = dataSet[.planarConfiguration]?.uint16Value.flatMap { Int($0) }

        // Parse Instance Number
        let instanceNumber = dataSet[.instanceNumber]?.integerStringValue?.value

        // Parse Patient Module
        let patientName = dataSet.string(for: .patientName)
        let patientID = dataSet.string(for: .patientID)
        let patientBirthDate = dataSet.date(for: .patientBirthDate)
        let patientSex = nonEmpty(dataSet.string(for: .patientSex))

        // Parse General Study Module
        let studyDate = dataSet.date(for: .studyDate)
        let studyTime = dataSet.time(for: .studyTime)
        let referringPhysicianName = nonEmpty(dataSet.string(for: .referringPhysicianName))
        let studyID = nonEmpty(dataSet.string(for: .studyID))
        let accessionNumber = nonEmpty(dataSet.string(for: .accessionNumber))
        let studyDescription = dataSet.string(for: .studyDescription)

        // Parse Series Module
        let modality = dataSet.string(for: .modality)
        let seriesDescription = dataSet.string(for: .seriesDescription)
        let seriesNumber = dataSet[.seriesNumber]?.integerStringValue?.value

        // Parse SC Equipment Module (values outside Table C.8-24 are tolerated)
        let conversionTypeString = dataSet.string(for: .conversionType) ?? ""
        let conversionType = ConversionType(dicomValue: conversionTypeString)

        // Parse SC Image Module
        let dateOfSecondaryCapture = dataSet.date(for: .dateOfSecondaryCapture)
        let timeOfSecondaryCapture = dataSet.time(for: .timeOfSecondaryCapture)
        let nominalScannedPixelSpacing = decimals(dataSet.strings(for: .nominalScannedPixelSpacing))

        // Parse Multi-frame vectors (Tables C.7-13, C.8-25c)
        let frameTime = decimals(dataSet.strings(for: .frameTime))?.first
        let frameTimeVector = decimals(dataSet.strings(for: .frameTimeVector))
        let pageNumberVector = dataSet.strings(for: .pageNumberVector).flatMap { values -> [Int]? in
            let parsed = values.compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
            return parsed.count == values.count && !parsed.isEmpty ? parsed : nil
        }
        let frameLabelVector = dataSet.strings(for: .frameLabelVector).flatMap { $0.isEmpty ? nil : $0 }

        // Parse SC Multi-frame Image Module rescale
        let rescaleIntercept = decimals(dataSet.strings(for: .rescaleIntercept))?.first
        let rescaleSlope = decimals(dataSet.strings(for: .rescaleSlope))?.first
        let rescaleType = nonEmpty(dataSet.string(for: .rescaleType))

        // Parse General Image Module
        let imageTypeString = dataSet.string(for: .imageType)
        let imageType = imageTypeString?.components(separatedBy: "\\")
        let derivationDescription = dataSet.string(for: .derivationDescription)
        let burnedInAnnotation = dataSet.string(for: .burnedInAnnotation)
        let patientOrientation = dataSet.strings(for: .patientOrientation).flatMap { $0.isEmpty ? nil : $0 }

        // Parse Content Date/Time
        let contentDate = dataSet.date(for: .contentDate)
        let contentTime = dataSet.time(for: .contentTime)

        // Parse Pixel Data
        let pixelData = dataSet[.pixelData]?.valueData

        return SecondaryCaptureImage(
            sopInstanceUID: sopInstanceUID,
            sopClassUID: sopClassUID,
            studyInstanceUID: studyInstanceUID,
            seriesInstanceUID: seriesInstanceUID,
            instanceNumber: instanceNumber,
            patientName: patientName,
            patientID: patientID,
            modality: modality,
            seriesDescription: seriesDescription,
            seriesNumber: seriesNumber,
            conversionType: conversionType,
            dateOfSecondaryCapture: dateOfSecondaryCapture,
            timeOfSecondaryCapture: timeOfSecondaryCapture,
            rows: Int(rowsValue),
            columns: Int(columnsValue),
            numberOfFrames: numberOfFrames,
            samplesPerPixel: samplesPerPixel,
            photometricInterpretation: photometricInterpretation,
            bitsAllocated: bitsAllocated,
            bitsStored: bitsStored,
            highBit: highBit,
            pixelRepresentation: pixelRepresentation,
            planarConfiguration: planarConfiguration,
            imageType: imageType,
            derivationDescription: derivationDescription,
            burnedInAnnotation: burnedInAnnotation,
            contentDate: contentDate,
            contentTime: contentTime,
            pixelData: pixelData,
            patientBirthDate: patientBirthDate,
            patientSex: patientSex,
            studyDate: studyDate,
            studyTime: studyTime,
            referringPhysicianName: referringPhysicianName,
            studyID: studyID,
            accessionNumber: accessionNumber,
            studyDescription: studyDescription,
            nominalScannedPixelSpacing: nominalScannedPixelSpacing,
            patientOrientation: patientOrientation,
            frameTime: frameTime,
            frameTimeVector: frameTimeVector,
            pageNumberVector: pageNumberVector,
            frameLabelVector: frameLabelVector,
            rescaleIntercept: rescaleIntercept,
            rescaleSlope: rescaleSlope,
            rescaleType: rescaleType
        )
    }

    /// nil for an absent or zero-length (Type 2 empty) value.
    private static func nonEmpty(_ value: String?) -> String? {
        guard let value, !value.isEmpty else { return nil }
        return value
    }

    /// Parses a DS multi-value; nil when absent, empty or not all numeric.
    private static func decimals(_ values: [String]?) -> [Double]? {
        guard let values, !values.isEmpty else { return nil }
        let parsed = values.compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
        return parsed.count == values.count ? parsed : nil
    }
}
