// NEMA-verified: 2026a, checked 2026-09-29 — SOP Class UIDs match PS3.6 2026a Table A-1; Conversion Type Defined Terms (DV, DI, DF, WSD, SD, SI, DRW, SYN) per PS3.3 Table C.8-24; Type 1/2 attributes of Tables C.7-1, C.7-3, C.7-5a, C.7-9, C.7-14, C.8-25b, C.8-25c modelled
//
// SecondaryCaptureImage.swift
// DICOMKit
//
// Created by DICOMKit on 2026-02-09.
// Copyright © 2026 DICOMKit. All rights reserved.
//

import Foundation
import DICOMCore

/// Represents a DICOM Secondary Capture Image IOD
///
/// Secondary Capture images are created by capturing images from non-DICOM
/// sources such as cameras, scanners, screen captures, or digitized film.
/// They support single-frame and multi-frame variants with various bit depths.
///
/// Supported SOP Classes:
/// - Secondary Capture Image Storage (1.2.840.10008.5.1.4.1.1.7)
/// - Multi-frame Single Bit SC Image Storage (1.2.840.10008.5.1.4.1.1.7.1)
/// - Multi-frame Grayscale Byte SC Image Storage (1.2.840.10008.5.1.4.1.1.7.2)
/// - Multi-frame Grayscale Word SC Image Storage (1.2.840.10008.5.1.4.1.1.7.3)
/// - Multi-frame True Color SC Image Storage (1.2.840.10008.5.1.4.1.1.7.4)
///
/// Reference: PS3.3 A.8 - Secondary Capture Image IOD
/// Reference: PS3.3 A.8.1 - Multi-frame SC Image IODs
public struct SecondaryCaptureImage: Sendable {

    // MARK: - SOP Class UIDs

    /// Secondary Capture Image Storage SOP Class UID
    public static let secondaryCaptureImageStorageUID = "1.2.840.10008.5.1.4.1.1.7"

    /// Multi-frame Single Bit Secondary Capture Image Storage SOP Class UID
    public static let multiframeSingleBitSCImageStorageUID = "1.2.840.10008.5.1.4.1.1.7.1"

    /// Multi-frame Grayscale Byte Secondary Capture Image Storage SOP Class UID
    public static let multiframeGrayscaleByteSCImageStorageUID = "1.2.840.10008.5.1.4.1.1.7.2"

    /// Multi-frame Grayscale Word Secondary Capture Image Storage SOP Class UID
    public static let multiframeGrayscaleWordSCImageStorageUID = "1.2.840.10008.5.1.4.1.1.7.3"

    /// Multi-frame True Color Secondary Capture Image Storage SOP Class UID
    public static let multiframeTrueColorSCImageStorageUID = "1.2.840.10008.5.1.4.1.1.7.4"

    // MARK: - Identification

    /// SOP Instance UID
    public let sopInstanceUID: String

    /// SOP Class UID
    public let sopClassUID: String

    /// Study Instance UID
    public let studyInstanceUID: String

    /// Series Instance UID
    public let seriesInstanceUID: String

    /// Instance Number
    public let instanceNumber: Int?

    // MARK: - Patient Information

    /// Patient Name
    public let patientName: String?

    /// Patient ID
    public let patientID: String?

    /// Patient's Birth Date (0010,0030), Type 2 in the Patient Module (Table C.7-1)
    public let patientBirthDate: DICOMDate?

    /// Patient's Sex (0010,0040), Type 2 in the Patient Module (Table C.7-1)
    public let patientSex: String?

    // MARK: - Study Information (General Study Module, Table C.7-3)

    /// Study Date (0008,0020), Type 2
    public let studyDate: DICOMDate?

    /// Study Time (0008,0030), Type 2
    public let studyTime: DICOMTime?

    /// Referring Physician's Name (0008,0090), Type 2
    public let referringPhysicianName: String?

    /// Study ID (0020,0010), Type 2
    public let studyID: String?

    /// Accession Number (0008,0050), Type 2
    public let accessionNumber: String?

    /// Study Description (0008,1030), Type 3
    public let studyDescription: String?

    // MARK: - Series Information

    /// Modality (typically "OT" for Secondary Capture)
    public let modality: String?

    /// Series Description
    public let seriesDescription: String?

    /// Series Number
    public let seriesNumber: Int?

    // MARK: - SC Equipment Module

    /// Conversion Type describing how the image was captured
    public let conversionType: ConversionType

    // MARK: - SC Image Module

    /// Date of Secondary Capture
    public let dateOfSecondaryCapture: DICOMDate?

    /// Time of Secondary Capture
    public let timeOfSecondaryCapture: DICOMTime?

    /// Nominal Scanned Pixel Spacing (0018,2010): adjacent row spacing, adjacent
    /// column spacing in mm on the digitized medium. Type 3 in the SC Image Module
    /// (Table C.8-25); Type 1C in the SC Multi-frame Image Module (Table C.8-25b):
    /// required if Conversion Type is DF.
    public let nominalScannedPixelSpacing: [Double]?

    // MARK: - Image Pixel Module

    /// Number of rows (height) in pixels
    public let rows: Int

    /// Number of columns (width) in pixels
    public let columns: Int

    /// Number of frames (1 for single-frame SC)
    public let numberOfFrames: Int

    /// Samples per pixel (1 for monochrome, 3 for color)
    public let samplesPerPixel: Int

    /// Photometric Interpretation (e.g., "MONOCHROME2", "RGB")
    public let photometricInterpretation: String

    /// Bits allocated per sample
    public let bitsAllocated: Int

    /// Bits stored per sample
    public let bitsStored: Int

    /// High bit position
    public let highBit: Int

    /// Pixel representation (0 = unsigned, 1 = signed)
    public let pixelRepresentation: Int

    /// Planar configuration (0 = interleaved, 1 = separate planes)
    public let planarConfiguration: Int?

    // MARK: - General Image Module

    /// Image Type values (e.g., ["DERIVED", "SECONDARY"])
    public let imageType: [String]?

    /// Derivation Description
    public let derivationDescription: String?

    /// Burned In Annotation ("YES" or "NO"); Type 3 in the General Image Module,
    /// Type 1 in the SC Multi-frame Image Module (Table C.8-25b).
    public let burnedInAnnotation: String?

    /// Patient Orientation (0020,0020), Type 2C in the General Image Module
    /// (Table C.7-9); always required for SC since the IOD has no Image
    /// Orientation (Patient). Two values, e.g. ["L", "P"]; empty when unknown.
    public let patientOrientation: [String]?

    // MARK: - Multi-frame / SC Multi-frame Vector Modules (Tables C.7-14, C.8-25c)

    /// Frame Time (0018,1063) in ms; when set, Frame Increment Pointer points to it (Cine Module).
    public let frameTime: Double?

    /// Frame Time Vector (0018,1065) in ms, one per frame.
    public let frameTimeVector: [Double]?

    /// Page Number Vector (0018,2001), one per frame.
    public let pageNumberVector: [Int]?

    /// Frame Label Vector (0018,2002), one per frame.
    public let frameLabelVector: [String]?

    // MARK: - SC Multi-frame Image Module rescale (Table C.8-25b, Type 1C)

    /// Rescale Intercept (0028,1052); defaults to 0 when written.
    public let rescaleIntercept: Double?

    /// Rescale Slope (0028,1053); defaults to 1 when written.
    public let rescaleSlope: Double?

    /// Rescale Type (0028,1054); defaults to "US" when written.
    public let rescaleType: String?

    // MARK: - Content Date/Time

    /// Content Date
    public let contentDate: DICOMDate?

    /// Content Time
    public let contentTime: DICOMTime?

    // MARK: - Pixel Data

    /// The pixel data
    public let pixelData: Data?

    // MARK: - Initialization

    /// Creates a SecondaryCaptureImage instance
    public init(
        sopInstanceUID: String,
        sopClassUID: String,
        studyInstanceUID: String,
        seriesInstanceUID: String,
        instanceNumber: Int? = nil,
        patientName: String? = nil,
        patientID: String? = nil,
        modality: String? = nil,
        seriesDescription: String? = nil,
        seriesNumber: Int? = nil,
        conversionType: ConversionType = .workstation,
        dateOfSecondaryCapture: DICOMDate? = nil,
        timeOfSecondaryCapture: DICOMTime? = nil,
        rows: Int,
        columns: Int,
        numberOfFrames: Int = 1,
        samplesPerPixel: Int = 1,
        photometricInterpretation: String = "MONOCHROME2",
        bitsAllocated: Int = 8,
        bitsStored: Int = 8,
        highBit: Int = 7,
        pixelRepresentation: Int = 0,
        planarConfiguration: Int? = nil,
        imageType: [String]? = nil,
        derivationDescription: String? = nil,
        burnedInAnnotation: String? = nil,
        contentDate: DICOMDate? = nil,
        contentTime: DICOMTime? = nil,
        pixelData: Data? = nil,
        patientBirthDate: DICOMDate? = nil,
        patientSex: String? = nil,
        studyDate: DICOMDate? = nil,
        studyTime: DICOMTime? = nil,
        referringPhysicianName: String? = nil,
        studyID: String? = nil,
        accessionNumber: String? = nil,
        studyDescription: String? = nil,
        nominalScannedPixelSpacing: [Double]? = nil,
        patientOrientation: [String]? = nil,
        frameTime: Double? = nil,
        frameTimeVector: [Double]? = nil,
        pageNumberVector: [Int]? = nil,
        frameLabelVector: [String]? = nil,
        rescaleIntercept: Double? = nil,
        rescaleSlope: Double? = nil,
        rescaleType: String? = nil
    ) {
        self.sopInstanceUID = sopInstanceUID
        self.sopClassUID = sopClassUID
        self.studyInstanceUID = studyInstanceUID
        self.seriesInstanceUID = seriesInstanceUID
        self.instanceNumber = instanceNumber
        self.patientName = patientName
        self.patientID = patientID
        self.modality = modality
        self.seriesDescription = seriesDescription
        self.seriesNumber = seriesNumber
        self.conversionType = conversionType
        self.dateOfSecondaryCapture = dateOfSecondaryCapture
        self.timeOfSecondaryCapture = timeOfSecondaryCapture
        self.rows = rows
        self.columns = columns
        self.numberOfFrames = numberOfFrames
        self.samplesPerPixel = samplesPerPixel
        self.photometricInterpretation = photometricInterpretation
        self.bitsAllocated = bitsAllocated
        self.bitsStored = bitsStored
        self.highBit = highBit
        self.pixelRepresentation = pixelRepresentation
        self.planarConfiguration = planarConfiguration
        self.imageType = imageType
        self.derivationDescription = derivationDescription
        self.burnedInAnnotation = burnedInAnnotation
        self.contentDate = contentDate
        self.contentTime = contentTime
        self.pixelData = pixelData
        self.patientBirthDate = patientBirthDate
        self.patientSex = patientSex
        self.studyDate = studyDate
        self.studyTime = studyTime
        self.referringPhysicianName = referringPhysicianName
        self.studyID = studyID
        self.accessionNumber = accessionNumber
        self.studyDescription = studyDescription
        self.nominalScannedPixelSpacing = nominalScannedPixelSpacing
        self.patientOrientation = patientOrientation
        self.frameTime = frameTime
        self.frameTimeVector = frameTimeVector
        self.pageNumberVector = pageNumberVector
        self.frameLabelVector = frameLabelVector
        self.rescaleIntercept = rescaleIntercept
        self.rescaleSlope = rescaleSlope
        self.rescaleType = rescaleType
    }

    /// The secondary capture type inferred from the SOP Class UID
    public var secondaryCaptureType: SecondaryCaptureType {
        return SecondaryCaptureType(sopClassUID: sopClassUID)
    }

    /// Whether this is a single-frame Secondary Capture image
    public var isSingleFrame: Bool {
        return sopClassUID == Self.secondaryCaptureImageStorageUID
    }

    /// Whether this is a multi-frame Secondary Capture image
    public var isMultiFrame: Bool {
        return !isSingleFrame
    }

    /// The image resolution as a string (e.g., "1920x1080")
    public var resolution: String {
        return "\(columns)x\(rows)"
    }

    /// Whether the image is monochrome
    public var isMonochrome: Bool {
        return photometricInterpretation.hasPrefix("MONOCHROME")
    }

    /// Whether the image is color
    public var isColor: Bool {
        return samplesPerPixel == 3
    }
}

// MARK: - Secondary Capture Type

/// Type of Secondary Capture based on SOP Class UID
public enum SecondaryCaptureType: String, Sendable {
    /// Standard single-frame Secondary Capture
    case singleFrame

    /// Multi-frame single bit (binary) Secondary Capture
    case multiframeSingleBit

    /// Multi-frame grayscale byte (8-bit) Secondary Capture
    case multiframeGrayscaleByte

    /// Multi-frame grayscale word (16-bit) Secondary Capture
    case multiframeGrayscaleWord

    /// Multi-frame true color (RGB) Secondary Capture
    case multiframeTrueColor

    /// Unknown or unrecognized type
    case unknown

    /// Creates a Secondary Capture type from a SOP Class UID
    public init(sopClassUID: String) {
        switch sopClassUID {
        case SecondaryCaptureImage.secondaryCaptureImageStorageUID:
            self = .singleFrame
        case SecondaryCaptureImage.multiframeSingleBitSCImageStorageUID:
            self = .multiframeSingleBit
        case SecondaryCaptureImage.multiframeGrayscaleByteSCImageStorageUID:
            self = .multiframeGrayscaleByte
        case SecondaryCaptureImage.multiframeGrayscaleWordSCImageStorageUID:
            self = .multiframeGrayscaleWord
        case SecondaryCaptureImage.multiframeTrueColorSCImageStorageUID:
            self = .multiframeTrueColor
        default:
            self = .unknown
        }
    }

    /// The SOP Class UID for this Secondary Capture type
    public var sopClassUID: String {
        switch self {
        case .singleFrame: return SecondaryCaptureImage.secondaryCaptureImageStorageUID
        case .multiframeSingleBit: return SecondaryCaptureImage.multiframeSingleBitSCImageStorageUID
        case .multiframeGrayscaleByte: return SecondaryCaptureImage.multiframeGrayscaleByteSCImageStorageUID
        case .multiframeGrayscaleWord: return SecondaryCaptureImage.multiframeGrayscaleWordSCImageStorageUID
        case .multiframeTrueColor: return SecondaryCaptureImage.multiframeTrueColorSCImageStorageUID
        case .unknown: return ""
        }
    }

    /// The default modality for Secondary Capture
    public var defaultModality: String {
        return Modality.ot.rawValue
    }

    /// Default pixel characteristics for this type
    public var defaultPixelCharacteristics: (samplesPerPixel: Int, bitsAllocated: Int, bitsStored: Int, highBit: Int, photometricInterpretation: String) {
        switch self {
        case .singleFrame:
            return (1, 8, 8, 7, "MONOCHROME2")
        case .multiframeSingleBit:
            return (1, 1, 1, 0, "MONOCHROME2")
        case .multiframeGrayscaleByte:
            return (1, 8, 8, 7, "MONOCHROME2")
        case .multiframeGrayscaleWord:
            return (1, 16, 16, 15, "MONOCHROME2")
        case .multiframeTrueColor:
            return (3, 8, 8, 7, "RGB")
        case .unknown:
            return (1, 8, 8, 7, "MONOCHROME2")
        }
    }

    /// Human-readable description of the type
    public var displayName: String {
        switch self {
        case .singleFrame: return "Secondary Capture"
        case .multiframeSingleBit: return "Multi-frame Single Bit SC"
        case .multiframeGrayscaleByte: return "Multi-frame Grayscale Byte SC"
        case .multiframeGrayscaleWord: return "Multi-frame Grayscale Word SC"
        case .multiframeTrueColor: return "Multi-frame True Color SC"
        case .unknown: return "Unknown SC"
        }
    }
}

// MARK: - Conversion Type

/// Describes the kind of image conversion that was performed
///
/// Conversion Type (0008,0064) is Type 1 in the SC Equipment Module. The cases
/// are the Defined Terms of PS3.3 2026a Table C.8-24: DV, DI, DF, WSD, SD, SI,
/// DRW, SYN.
///
/// Reference: PS3.3 C.8.6.1 - SC Equipment Module, Table C.8-24
public enum ConversionType: String, Sendable, CaseIterable {
    /// DV - Digitized Video
    case digitizedVideo = "DV"

    /// DI - Digital Interface
    case digitalInterface = "DI"

    /// DF - Digitized Film
    case digitizedFilm = "DF"

    /// WSD - Workstation
    case workstation = "WSD"

    /// SD - Scanned Document
    case scannedDocument = "SD"

    /// SI - Scanned Image
    case scannedImage = "SI"

    /// DRW - Drawing
    case drawing = "DRW"

    /// SYN - Synthetic Image
    case synthesized = "SYN"

    /// A value that is not one of the Table C.8-24 Defined Terms (parser tolerance only).
    ///
    /// Conversion Type is Type 1, so an empty value is not a legal encoding. Writers
    /// never emit this case: ``standardTerm`` maps it to `WSD` (Workstation), the
    /// term used for images captured from a display.
    @available(*, deprecated, message: "Conversion Type (0008,0064) is Type 1; there is no empty/unknown term in PS3.3 2026a Table C.8-24. Writers emit WSD for this case; use standardTerm.")
    case unknown = ""

    /// The Table C.8-24 term that serializers write for this case.
    ///
    /// Every Defined Term writes itself; the deprecated `.unknown` case writes
    /// `WSD` because a Type 1 attribute must carry a value.
    public var standardTerm: String {
        let raw = rawValue
        return raw.isEmpty ? ConversionType.workstation.rawValue : raw
    }

    /// The Defined Terms of PS3.3 2026a Table C.8-24, in table order.
    public static let definedTerms: [String] = ["DV", "DI", "DF", "WSD", "SD", "SI", "DRW", "SYN"]

    /// The Defined-Term cases only (the deprecated `.unknown` is not a term).
    public static var allCases: [ConversionType] {
        [.digitizedVideo, .digitalInterface, .digitizedFilm, .workstation,
         .scannedDocument, .scannedImage, .drawing, .synthesized]
    }

    /// Creates a ConversionType from its DICOM string value
    ///
    /// Values that are not Defined Terms are tolerated on read and map to the
    /// deprecated `.unknown` case; use ``init?(definedTerm:)`` for a strict parse.
    public init(dicomValue: String) {
        if let term = ConversionType(definedTerm: dicomValue) {
            self = term
        } else {
            self = ConversionType(rawValue: "")!
        }
    }

    /// Strict parse: nil unless the (trimmed) value is a Table C.8-24 Defined Term.
    public init?(definedTerm: String) {
        let trimmed = definedTerm.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, let term = ConversionType(rawValue: trimmed) else { return nil }
        self = term
    }

    /// Whether this is one of the Table C.8-24 Defined Terms (false only for the deprecated `.unknown`).
    public var isDefinedTerm: Bool { !rawValue.isEmpty }

    /// Human-readable description (the Table C.8-24 meanings)
    public var displayName: String {
        switch rawValue {
        case "DV": return "Digitized Video"
        case "DI": return "Digital Interface"
        case "DF": return "Digitized Film"
        case "WSD": return "Workstation"
        case "SD": return "Scanned Document"
        case "SI": return "Scanned Image"
        case "DRW": return "Drawing"
        case "SYN": return "Synthetic Image"
        default: return "Unknown"
        }
    }
}
