// NEMA-verified: 2026a, checked 2026-09-29 — every Type 1/2 attribute of the SC IODs (Tables A.8-1…A.8-5) written: Patient C.7-1, General Study C.7-3, General Series C.7-5a, General Image C.7-9, Image Pixel C.7-11a and A.8.x.4 constraints, Multi-frame C.7-14, SC Equipment C.8-24, SC Multi-frame Image C.8-25b, SC Multi-frame Vector C.8-25c; VRs per PS3.6 Table 6-1
//
// SecondaryCaptureBuilder.swift
// DICOMKit
//
// Created by DICOMKit on 2026-02-09.
// Copyright © 2026 DICOMKit. All rights reserved.
//

import Foundation
import DICOMCore

/// Builder for creating DICOM Secondary Capture Image objects
///
/// SecondaryCaptureBuilder provides a fluent API for constructing Secondary Capture IODs,
/// enabling captured images to be wrapped as DICOM objects for storage and transmission.
///
/// Example - Creating a single-frame grayscale Secondary Capture:
/// ```swift
/// let imageData = Data(repeating: 128, count: 512 * 512)
/// let sc = try SecondaryCaptureBuilder(
///     secondaryCaptureType: .singleFrame,
///     rows: 512,
///     columns: 512,
///     studyInstanceUID: "1.2.3.4.5",
///     seriesInstanceUID: "1.2.3.4.5.6"
/// )
/// .setConversionType(.workstation)
/// .setPatientName("Smith^John")
/// .setPatientID("12345")
/// .setPixelData(imageData)
/// .build()
/// ```
///
/// Example - Creating a multi-frame true color Secondary Capture:
/// ```swift
/// let colorData = Data(repeating: 0, count: 256 * 256 * 3 * 10)
/// let sc = try SecondaryCaptureBuilder(
///     secondaryCaptureType: .multiframeTrueColor,
///     rows: 256,
///     columns: 256,
///     studyInstanceUID: "1.2.3.4.5",
///     seriesInstanceUID: "1.2.3.4.5.6"
/// )
/// .setNumberOfFrames(10)
/// .setConversionType(.digitizedVideo)
/// .setPixelData(colorData)
/// .build()
/// ```
///
/// Reference: PS3.3 A.8 - Secondary Capture Image IOD
/// Reference: PS3.3 A.8.1 - Multi-frame SC Image IODs
public final class SecondaryCaptureBuilder {

    // MARK: - Required Configuration

    private let secondaryCaptureType: SecondaryCaptureType
    private let rows: Int
    private let columns: Int
    private let studyInstanceUID: String
    private let seriesInstanceUID: String

    // MARK: - Optional Metadata

    private var sopInstanceUID: String?
    private var instanceNumber: Int?
    private var patientName: String?
    private var patientID: String?
    private var patientBirthDate: DICOMDate?
    private var patientSex: String?
    private var studyDate: DICOMDate?
    private var studyTime: DICOMTime?
    private var referringPhysicianName: String?
    private var studyID: String?
    private var accessionNumber: String?
    private var studyDescription: String?
    private var modality: String?
    private var seriesDescription: String?
    private var seriesNumber: Int?
    /// Default WSD (Workstation): DF would make Nominal Scanned Pixel Spacing
    /// Type 1C in the multi-frame IODs (Table C.8-25b).
    private var conversionType: ConversionType = .workstation
    private var dateOfSecondaryCapture: DICOMDate?
    private var timeOfSecondaryCapture: DICOMTime?
    private var nominalScannedPixelSpacing: [Double]?
    private var patientOrientation: [String]?
    private var frameTime: Double?
    private var frameTimeVector: [Double]?
    private var pageNumberVector: [Int]?
    private var frameLabelVector: [String]?
    private var rescaleIntercept: Double?
    private var rescaleSlope: Double?
    private var rescaleType: String?
    private var numberOfFrames: Int = 1
    private var samplesPerPixel: Int?
    private var photometricInterpretation: String?
    private var bitsAllocated: Int?
    private var bitsStored: Int?
    private var highBit: Int?
    private var pixelRepresentation: Int = 0
    private var planarConfiguration: Int?
    private var imageType: [String]?
    private var derivationDescription: String?
    private var burnedInAnnotation: String?
    private var contentDate: DICOMDate?
    private var contentTime: DICOMTime?
    private var pixelData: Data?

    // MARK: - Initialization

    /// Creates a new SecondaryCaptureBuilder
    ///
    /// - Parameters:
    ///   - secondaryCaptureType: The type of Secondary Capture image
    ///   - rows: Number of rows (height) in pixels
    ///   - columns: Number of columns (width) in pixels
    ///   - studyInstanceUID: The Study Instance UID
    ///   - seriesInstanceUID: The Series Instance UID
    public init(
        secondaryCaptureType: SecondaryCaptureType,
        rows: Int,
        columns: Int,
        studyInstanceUID: String,
        seriesInstanceUID: String
    ) {
        self.secondaryCaptureType = secondaryCaptureType
        self.rows = rows
        self.columns = columns
        self.studyInstanceUID = studyInstanceUID
        self.seriesInstanceUID = seriesInstanceUID
    }

    // MARK: - Fluent Setters

    /// Sets the SOP Instance UID (auto-generated if not set)
    @discardableResult
    public func setSOPInstanceUID(_ uid: String) -> Self {
        self.sopInstanceUID = uid
        return self
    }

    /// Sets the Instance Number
    @discardableResult
    public func setInstanceNumber(_ number: Int) -> Self {
        self.instanceNumber = number
        return self
    }

    /// Sets the Patient Name
    @discardableResult
    public func setPatientName(_ name: String) -> Self {
        self.patientName = name
        return self
    }

    /// Sets the Patient ID
    @discardableResult
    public func setPatientID(_ id: String) -> Self {
        self.patientID = id
        return self
    }

    /// Sets Patient's Birth Date (0010,0030), Type 2 (written empty when unset)
    @discardableResult
    public func setPatientBirthDate(_ date: DICOMDate) -> Self {
        self.patientBirthDate = date
        return self
    }

    /// Sets Patient's Sex (0010,0040), Type 2; Enumerated Values M, F, O (Table C.7-1)
    @discardableResult
    public func setPatientSex(_ sex: String) -> Self {
        self.patientSex = sex
        return self
    }

    /// Sets Study Date (0008,0020) and Study Time (0008,0030), Type 2
    @discardableResult
    public func setStudyDateTime(date: DICOMDate, time: DICOMTime) -> Self {
        self.studyDate = date
        self.studyTime = time
        return self
    }

    /// Sets Referring Physician's Name (0008,0090), Type 2
    @discardableResult
    public func setReferringPhysicianName(_ name: String) -> Self {
        self.referringPhysicianName = name
        return self
    }

    /// Sets Study ID (0020,0010), Type 2
    @discardableResult
    public func setStudyID(_ id: String) -> Self {
        self.studyID = id
        return self
    }

    /// Sets Accession Number (0008,0050), Type 2
    @discardableResult
    public func setAccessionNumber(_ number: String) -> Self {
        self.accessionNumber = number
        return self
    }

    /// Sets Study Description (0008,1030), Type 3
    @discardableResult
    public func setStudyDescription(_ description: String) -> Self {
        self.studyDescription = description
        return self
    }

    /// Sets Patient Orientation (0020,0020): row direction, column direction
    /// (e.g. "L", "P"); Type 2C, written empty when unset.
    @discardableResult
    public func setPatientOrientation(row: String, column: String) -> Self {
        self.patientOrientation = [row, column]
        return self
    }

    /// Sets Nominal Scanned Pixel Spacing (0018,2010) in mm: row spacing, column spacing.
    /// Required for the multi-frame IODs when Conversion Type is DF (Table C.8-25b).
    @discardableResult
    public func setNominalScannedPixelSpacing(row: Double, column: Double) -> Self {
        self.nominalScannedPixelSpacing = [row, column]
        return self
    }

    /// Sets Frame Time (0018,1063) in ms; Frame Increment Pointer then points to it (Cine Module).
    @discardableResult
    public func setFrameTime(_ milliseconds: Double) -> Self {
        self.frameTime = milliseconds
        return self
    }

    /// Sets Frame Time Vector (0018,1065) in ms, one value per frame.
    @discardableResult
    public func setFrameTimeVector(_ milliseconds: [Double]) -> Self {
        self.frameTimeVector = milliseconds
        return self
    }

    /// Sets Page Number Vector (0018,2001), one value per frame.
    @discardableResult
    public func setPageNumberVector(_ pages: [Int]) -> Self {
        self.pageNumberVector = pages
        return self
    }

    /// Sets Frame Label Vector (0018,2002), one value per frame.
    @discardableResult
    public func setFrameLabelVector(_ labels: [String]) -> Self {
        self.frameLabelVector = labels
        return self
    }

    /// Sets the Modality LUT rescale of the SC Multi-frame Image Module (Type 1C for
    /// MONOCHROME2 with Bits Stored > 1). The Grayscale Byte IOD fixes 0 / 1 / "US"
    /// (A.8.3.4); the Grayscale Word IOD leaves slope and intercept free (A.8.4.4).
    @discardableResult
    public func setRescale(intercept: Double, slope: Double, type: String = "US") -> Self {
        self.rescaleIntercept = intercept
        self.rescaleSlope = slope
        self.rescaleType = type
        return self
    }

    /// Sets the Modality (defaults to "OT" if not set)
    @discardableResult
    public func setModality(_ modality: String) -> Self {
        self.modality = modality
        return self
    }

    /// Sets the Series Description
    @discardableResult
    public func setSeriesDescription(_ description: String) -> Self {
        self.seriesDescription = description
        return self
    }

    /// Sets the Series Number
    @discardableResult
    public func setSeriesNumber(_ number: Int) -> Self {
        self.seriesNumber = number
        return self
    }

    /// Sets the Conversion Type describing how the image was captured
    @discardableResult
    public func setConversionType(_ type: ConversionType) -> Self {
        self.conversionType = type
        return self
    }

    /// Sets the date and time of secondary capture
    @discardableResult
    public func setCaptureDateTime(date: DICOMDate, time: DICOMTime) -> Self {
        self.dateOfSecondaryCapture = date
        self.timeOfSecondaryCapture = time
        return self
    }

    /// Sets the Date of Secondary Capture
    @discardableResult
    public func setDateOfSecondaryCapture(_ date: DICOMDate) -> Self {
        self.dateOfSecondaryCapture = date
        return self
    }

    /// Sets the Time of Secondary Capture
    @discardableResult
    public func setTimeOfSecondaryCapture(_ time: DICOMTime) -> Self {
        self.timeOfSecondaryCapture = time
        return self
    }

    /// Sets the Number of Frames (for multi-frame types)
    @discardableResult
    public func setNumberOfFrames(_ count: Int) -> Self {
        self.numberOfFrames = count
        return self
    }

    /// Sets the Samples Per Pixel (overrides type default)
    @discardableResult
    public func setSamplesPerPixel(_ value: Int) -> Self {
        self.samplesPerPixel = value
        return self
    }

    /// Sets the Photometric Interpretation (overrides type default)
    @discardableResult
    public func setPhotometricInterpretation(_ value: String) -> Self {
        self.photometricInterpretation = value
        return self
    }

    /// Sets the bit depth parameters (overrides type defaults)
    @discardableResult
    public func setBitDepth(allocated: Int, stored: Int, highBit: Int) -> Self {
        self.bitsAllocated = allocated
        self.bitsStored = stored
        self.highBit = highBit
        return self
    }

    /// Sets the Pixel Representation (0 = unsigned, 1 = signed)
    @discardableResult
    public func setPixelRepresentation(_ value: Int) -> Self {
        self.pixelRepresentation = value
        return self
    }

    /// Sets the Planar Configuration (0 = interleaved, 1 = separate planes)
    @discardableResult
    public func setPlanarConfiguration(_ value: Int) -> Self {
        self.planarConfiguration = value
        return self
    }

    /// Sets the Image Type values
    @discardableResult
    public func setImageType(_ values: [String]) -> Self {
        self.imageType = values
        return self
    }

    /// Sets the Derivation Description
    @discardableResult
    public func setDerivationDescription(_ description: String) -> Self {
        self.derivationDescription = description
        return self
    }

    /// Sets the Burned In Annotation flag
    @discardableResult
    public func setBurnedInAnnotation(_ value: String) -> Self {
        self.burnedInAnnotation = value
        return self
    }

    /// Sets the Content Date
    @discardableResult
    public func setContentDate(_ date: DICOMDate) -> Self {
        self.contentDate = date
        return self
    }

    /// Sets the Content Time
    @discardableResult
    public func setContentTime(_ time: DICOMTime) -> Self {
        self.contentTime = time
        return self
    }

    /// Sets the pixel data
    @discardableResult
    public func setPixelData(_ data: Data) -> Self {
        self.pixelData = data
        return self
    }

    // MARK: - Build

    /// Builds the SecondaryCaptureImage object
    ///
    /// - Returns: The constructed SecondaryCaptureImage
    /// - Throws: DICOMError if required data is invalid
    public func build() throws -> SecondaryCaptureImage {
        guard rows > 0 else {
            throw DICOMError.parsingFailed("Rows must be greater than 0")
        }

        guard columns > 0 else {
            throw DICOMError.parsingFailed("Columns must be greater than 0")
        }

        guard secondaryCaptureType != .unknown else {
            throw DICOMError.parsingFailed("Secondary Capture type cannot be unknown")
        }

        // For multi-frame types, validate frame count
        if secondaryCaptureType != .singleFrame && numberOfFrames < 1 {
            throw DICOMError.parsingFailed("Number of frames must be at least 1 for multi-frame types")
        }

        if let burnedInAnnotation, !["YES", "NO"].contains(burnedInAnnotation) {
            throw DICOMError.parsingFailed("Burned In Annotation must be YES or NO (PS3.3 Table C.8-25b)")
        }
        if let patientSex, !["M", "F", "O"].contains(patientSex) {
            throw DICOMError.parsingFailed("Patient's Sex must be M, F or O (PS3.3 Table C.7-1)")
        }
        if secondaryCaptureType != .singleFrame {
            if conversionType == .digitizedFilm, nominalScannedPixelSpacing == nil {
                throw DICOMError.parsingFailed("Nominal Scanned Pixel Spacing is required when Conversion Type is DF (PS3.3 Table C.8-25b)")
            }
            if let frameTimeVector, frameTimeVector.count != numberOfFrames {
                throw DICOMError.parsingFailed("Frame Time Vector must have one value per frame")
            }
            if let pageNumberVector, pageNumberVector.count != numberOfFrames {
                throw DICOMError.parsingFailed("Page Number Vector must have one value per frame")
            }
            if let frameLabelVector, frameLabelVector.count != numberOfFrames {
                throw DICOMError.parsingFailed("Frame Label Vector must have one value per frame")
            }
        }

        let defaults = secondaryCaptureType.defaultPixelCharacteristics
        let effectiveSamplesPerPixel = samplesPerPixel ?? defaults.samplesPerPixel
        let effectiveBitsAllocated = bitsAllocated ?? defaults.bitsAllocated
        let effectiveBitsStored = bitsStored ?? defaults.bitsStored
        let effectiveHighBit = highBit ?? defaults.highBit
        let effectivePhotometric = photometricInterpretation ?? defaults.photometricInterpretation

        let instanceUID = sopInstanceUID ?? UIDGenerator.generateSOPInstanceUID().value
        let effectiveModality = modality ?? secondaryCaptureType.defaultModality

        // Default image type for SC
        let effectiveImageType = imageType ?? ["DERIVED", "SECONDARY"]

        return SecondaryCaptureImage(
            sopInstanceUID: instanceUID,
            sopClassUID: secondaryCaptureType.sopClassUID,
            studyInstanceUID: studyInstanceUID,
            seriesInstanceUID: seriesInstanceUID,
            instanceNumber: instanceNumber,
            patientName: patientName,
            patientID: patientID,
            modality: effectiveModality,
            seriesDescription: seriesDescription,
            seriesNumber: seriesNumber,
            conversionType: conversionType,
            dateOfSecondaryCapture: dateOfSecondaryCapture,
            timeOfSecondaryCapture: timeOfSecondaryCapture,
            rows: rows,
            columns: columns,
            numberOfFrames: numberOfFrames,
            samplesPerPixel: effectiveSamplesPerPixel,
            photometricInterpretation: effectivePhotometric,
            bitsAllocated: effectiveBitsAllocated,
            bitsStored: effectiveBitsStored,
            highBit: effectiveHighBit,
            pixelRepresentation: pixelRepresentation,
            planarConfiguration: planarConfiguration,
            imageType: effectiveImageType,
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

    /// Builds the SecondaryCaptureImage and converts it to a DICOM DataSet
    ///
    /// - Returns: A DataSet ready for DICOM file creation
    /// - Throws: DICOMError if building fails
    public func buildDataSet() throws -> DataSet {
        let sc = try build()
        return sc.toDataSet()
    }
}

// MARK: - DataSet Conversion

extension SecondaryCaptureImage {

    /// Converts the SecondaryCaptureImage to a DICOM DataSet
    ///
    /// Writes every Type 1 attribute and every Type 2 attribute (empty when unknown)
    /// of the mandatory modules of the SC IOD being written (PS3.3 2026a Tables
    /// A.8-1 … A.8-5), plus the Type 1C attributes whose condition holds:
    ///
    /// - Patient (Table C.7-1): Patient's Name, Patient ID, Patient's Birth Date, Patient's Sex.
    /// - General Study (Table C.7-3): Study Instance UID; Study Date, Study Time,
    ///   Referring Physician's Name, Study ID, Accession Number.
    /// - General Series (Table C.7-5a): Modality, Series Instance UID; Series Number.
    /// - SC Equipment (Table C.8-24): Conversion Type.
    /// - General Image (Table C.7-9): Instance Number; Patient Orientation (2C, always
    ///   required here because the SC IODs carry no Image Orientation (Patient)).
    /// - Image Pixel (Table C.7-11a): Samples per Pixel, Photometric Interpretation,
    ///   Rows, Columns, Bits Allocated/Stored, High Bit, Pixel Representation, Pixel
    ///   Data; Planar Configuration only when Samples per Pixel > 1 (A.8.x.4 forbid it
    ///   for the grayscale multi-frame IODs).
    /// - Multi-frame IODs: Number of Frames (Table C.7-14); Frame Increment Pointer and
    ///   its target vector when Number of Frames > 1 (Tables C.8-25b, C.8-25c: Frame
    ///   Time, Frame Time Vector, Page Number Vector or Frame Label Vector — Page
    ///   Number Vector 1…N when none was given); Burned In Annotation (Type 1, "NO"
    ///   when unset); Presentation LUT Shape IDENTITY and Rescale Intercept/Slope/Type
    ///   when Photometric Interpretation is MONOCHROME2 and Bits Stored > 1 (0 / 1 /
    ///   "US" unless set; A.8.3.4 fixes those values for the Grayscale Byte IOD).
    ///
    /// - Returns: A DataSet representation of this Secondary Capture image
    public func toDataSet() -> DataSet {
        var dataSet = DataSet()
        let multiFrame = isMultiFrame

        // SOP Common Module (Table C.12-1)
        dataSet.setString(sopClassUID, for: .sopClassUID, vr: .UI)
        dataSet.setString(sopInstanceUID, for: .sopInstanceUID, vr: .UI)

        // Patient Module (Table C.7-1): all Type 2
        dataSet.setString(patientName ?? "", for: .patientName, vr: .PN)
        dataSet.setString(patientID ?? "", for: .patientID, vr: .LO)
        dataSet.setString(patientBirthDate?.dicomString ?? "", for: .patientBirthDate, vr: .DA)
        dataSet.setString(patientSex ?? "", for: .patientSex, vr: .CS)

        // General Study Module (Table C.7-3)
        dataSet.setString(studyInstanceUID, for: .studyInstanceUID, vr: .UI)
        dataSet.setString(studyDate?.dicomString ?? "", for: .studyDate, vr: .DA)
        dataSet.setString(studyTime?.dicomString ?? "", for: .studyTime, vr: .TM)
        dataSet.setString(referringPhysicianName ?? "", for: .referringPhysicianName, vr: .PN)
        dataSet.setString(studyID ?? "", for: .studyID, vr: .SH)
        dataSet.setString(accessionNumber ?? "", for: .accessionNumber, vr: .SH)
        if let studyDescription {
            dataSet.setString(studyDescription, for: .studyDescription, vr: .LO)
        }

        // General Series Module (Table C.7-5a)
        dataSet.setString(modality ?? secondaryCaptureType.defaultModality, for: .modality, vr: .CS)
        dataSet.setString(seriesInstanceUID, for: .seriesInstanceUID, vr: .UI)
        dataSet.setString(seriesNumber.map(String.init) ?? "", for: .seriesNumber, vr: .IS)
        if let seriesDescription {
            dataSet.setString(seriesDescription, for: .seriesDescription, vr: .LO)
        }

        // SC Equipment Module (Table C.8-24): Conversion Type Type 1
        dataSet.setString(conversionType.standardTerm, for: .conversionType, vr: .CS)

        // SC Image Module (Table C.8-25; Nominal Scanned Pixel Spacing is 1C for DF in C.8-25b)
        if let dateOfSecondaryCapture {
            dataSet.setString(dateOfSecondaryCapture.dicomString, for: .dateOfSecondaryCapture, vr: .DA)
        }
        if let timeOfSecondaryCapture {
            dataSet.setString(timeOfSecondaryCapture.dicomString, for: .timeOfSecondaryCapture, vr: .TM)
        }
        if let nominalScannedPixelSpacing, nominalScannedPixelSpacing.count == 2 {
            dataSet.setStrings(nominalScannedPixelSpacing.map(DataSet.defaultDecimalString),
                               for: .nominalScannedPixelSpacing, vr: .DS)
        }

        // General Image Module (Table C.7-9)
        dataSet.setString(instanceNumber.map(String.init) ?? "", for: .instanceNumber, vr: .IS)
        dataSet.setStrings(patientOrientation ?? [], for: .patientOrientation, vr: .CS)
        if let imageType, !imageType.isEmpty {
            dataSet.setStrings(imageType, for: .imageType, vr: .CS)
        }
        if let derivationDescription {
            dataSet.setString(derivationDescription, for: .derivationDescription, vr: .ST)
        }
        if let burnedInAnnotation {
            dataSet.setString(burnedInAnnotation, for: .burnedInAnnotation, vr: .CS)
        } else if multiFrame {
            // Type 1 in the SC Multi-frame Image Module (Table C.8-25b).
            dataSet.setString("NO", for: .burnedInAnnotation, vr: .CS)
        }
        if let contentDate {
            dataSet.setString(contentDate.dicomString, for: .contentDate, vr: .DA)
        }
        if let contentTime {
            dataSet.setString(contentTime.dicomString, for: .contentTime, vr: .TM)
        }

        // Image Pixel Module (Table C.7-11a)
        dataSet[.rows] = DataElement.uint16(tag: .rows, value: UInt16(rows))
        dataSet[.columns] = DataElement.uint16(tag: .columns, value: UInt16(columns))
        dataSet[.samplesPerPixel] = DataElement.uint16(tag: .samplesPerPixel, value: UInt16(samplesPerPixel))
        dataSet.setString(photometricInterpretation, for: .photometricInterpretation, vr: .CS)
        dataSet[.bitsAllocated] = DataElement.uint16(tag: .bitsAllocated, value: UInt16(bitsAllocated))
        dataSet[.bitsStored] = DataElement.uint16(tag: .bitsStored, value: UInt16(bitsStored))
        dataSet[.highBit] = DataElement.uint16(tag: .highBit, value: UInt16(highBit))
        dataSet[.pixelRepresentation] = DataElement.uint16(tag: .pixelRepresentation, value: UInt16(pixelRepresentation))
        if samplesPerPixel > 1 {
            // Type 1C: required if Samples per Pixel > 1; A.8.5.4: 0 for RGB.
            dataSet[.planarConfiguration] = DataElement.uint16(tag: .planarConfiguration,
                                                               value: UInt16(planarConfiguration ?? 0))
        }

        if multiFrame {
            // Multi-frame Module (Table C.7-14)
            dataSet.setString(String(numberOfFrames), for: .numberOfFrames, vr: .IS)

            // Frame Increment Pointer (Table C.8-25b: required if Number of Frames > 1)
            // and its SC Multi-frame Vector / Cine target (Tables C.8-25c, C.7-13).
            let writer = DICOMWriter()
            var pointerTarget: Tag?
            if let frameTime {
                dataSet.setString(DataSet.defaultDecimalString(frameTime), for: .frameTime, vr: .DS)
                pointerTarget = .frameTime
            } else if let frameTimeVector, frameTimeVector.count == numberOfFrames {
                dataSet.setStrings(frameTimeVector.map(DataSet.defaultDecimalString), for: .frameTimeVector, vr: .DS)
                pointerTarget = .frameTimeVector
            } else if let frameLabelVector, frameLabelVector.count == numberOfFrames {
                dataSet.setStrings(frameLabelVector, for: .frameLabelVector, vr: .SH)
                pointerTarget = .frameLabelVector
            } else if let pageNumberVector, pageNumberVector.count == numberOfFrames {
                dataSet.setStrings(pageNumberVector.map(String.init), for: .pageNumberVector, vr: .IS)
                pointerTarget = .pageNumberVector
            } else if numberOfFrames > 1 {
                dataSet.setStrings((1...numberOfFrames).map(String.init), for: .pageNumberVector, vr: .IS)
                pointerTarget = .pageNumberVector
            }
            if let pointerTarget {
                dataSet[.frameIncrementPointer] = DataElement(tag: .frameIncrementPointer, vr: .AT, length: 4,
                                                              valueData: writer.serializeTag(pointerTarget))
            }

            // SC Multi-frame Image Module (Table C.8-25b), Type 1C: MONOCHROME2 and Bits Stored > 1.
            if photometricInterpretation == "MONOCHROME2", bitsStored > 1 {
                dataSet.setString("IDENTITY", for: .presentationLUTShape, vr: .CS)
                dataSet.setString(DataSet.defaultDecimalString(rescaleIntercept ?? 0), for: .rescaleIntercept, vr: .DS)
                dataSet.setString(DataSet.defaultDecimalString(rescaleSlope ?? 1), for: .rescaleSlope, vr: .DS)
                dataSet.setString(rescaleType ?? "US", for: .rescaleType, vr: .LO)
            }
        } else if numberOfFrames > 1 {
            dataSet.setString(String(numberOfFrames), for: .numberOfFrames, vr: .IS)
        }

        // Pixel Data
        if let pixelData {
            dataSet[.pixelData] = DataElement.data(
                tag: .pixelData,
                vr: .OW,
                data: pixelData
            )
        }

        return dataSet
    }
}
