// NEMA-verified: 2026a, checked 2026-10-01 — Encapsulated Document Length (0042,0015) UL written with the unpadded byte count (Table C.24-2) (D182); Specific Character Set ISO_IR 192 when a text value is not ASCII (Table C.12-1 Type 1C, C.12-5) (D182); every Type 1/2 attribute of the Mandatory modules of PS3.3 2026a Tables A.45.1-1 (PDF), A.45.2-1 (CDA), A.85.1-1 (STL), A.85.2-1 (OBJ), A.85.3-1 (MTL): C.7-1, C.7-3, C.24-1, C.7-8, C.8-24 (Conversion Type Defined Terms), C.7-8b, C.7-6, C.35.1-1 (CID 7063), C.24-2, C.12-1; MIME/Modality Enumerated Values A.45.1.4.1, A.45.2.4, A.85.x.4.2/.3; VRs PS3.6 Table 6-1
//
// EncapsulatedDocumentBuilder.swift
// DICOMKit
//
// Created by DICOMKit on 2026-02-06.
// Copyright © 2026 DICOMKit. All rights reserved.
//

import Foundation
import DICOMCore

/// Builder for creating DICOM Encapsulated Document objects
///
/// EncapsulatedDocumentBuilder provides a fluent API for constructing Encapsulated Document
/// IODs, enabling PDF files, CDA documents, and other document types to be wrapped as DICOM
/// objects for storage and transmission.
///
/// Example - Encapsulating a PDF:
/// ```swift
/// let pdfData = try Data(contentsOf: pdfURL)
/// let document = try EncapsulatedDocumentBuilder(
///     documentData: pdfData,
///     mimeType: "application/pdf",
///     documentType: .pdf,
///     studyInstanceUID: "1.2.3.4.5",
///     seriesInstanceUID: "1.2.3.4.5.6"
/// )
/// .setDocumentTitle("Radiology Report")
/// .setPatientName("Smith^John")
/// .setPatientID("12345")
/// .setModality("DOC")
/// .build()
/// ```
///
/// Example - Encapsulating a CDA document:
/// ```swift
/// let cdaData = cdaXMLString.data(using: .utf8)!
/// let document = try EncapsulatedDocumentBuilder(
///     documentData: cdaData,
///     mimeType: "text/XML",
///     documentType: .cda,
///     studyInstanceUID: "1.2.3.4.5",
///     seriesInstanceUID: "1.2.3.4.5.6"
/// )
/// .setDocumentTitle("Discharge Summary")
/// .setHL7InstanceIdentifier("2.16.840.1.113883.19.999.1")
/// .build()
/// ```
///
/// ## IOD completeness
///
/// `buildDataSet()` writes every Type 1 and Type 2 attribute of the Mandatory modules
/// of the IOD selected by `documentType` (PS3.3 Tables A.45.1-1, A.45.2-1, A.85.1-1,
/// A.85.2-1, A.85.3-1). Type 2 attributes whose value is unknown are written empty
/// (PS3.5 7.4.3). Type 1 attributes must carry a value (PS3.5 7.4.1): `build()` throws
/// when one cannot be supplied, and applies these library defaults otherwise:
///
/// - Modality (0008,0060): `DOC` for PDF/CDA (Defined Term, C.7.3.1.1.1); `M3D` for
///   STL/OBJ/MTL (Enumerated Value, A.85.1.4.3 / A.85.2.4.3 / A.85.3.4.3).
/// - Series Number (0020,0011) and Instance Number (0020,0013): `1`.
/// - Burned In Annotation (0028,0301): `YES` unless ``setBurnedInAnnotation(_:)`` says
///   otherwise — a report or CDA normally names the patient, and Table C.24-2 equates
///   identifying text in the document with burned-in annotation.
/// - Conversion Type (0008,0064) for PDF/CDA (Table C.8-24 SC Equipment): `WSD`
///   (Workstation), one of the Defined Terms DV, DI, DF, WSD, SD, SI, DRW, SYN.
/// - Enhanced General Equipment (Table C.7-8b) for STL/OBJ/MTL: this library's identity
///   (Manufacturer `DICOMKit`, Manufacturer's Model Name `EncapsulatedDocumentBuilder`,
///   Software Versions the library version, Device Serial Number the library's
///   Implementation Class UID) unless the caller sets the real equipment.
/// - Frame of Reference UID (0020,0052) for STL/OBJ: a freshly generated UID.
/// - Measurement Units Code Sequence (0040,08EA) for STL/OBJ/MTL: `(mm, UCUM, "mm")`
///   from CID 7063 unless ``setMeasurementUnits(codeValue:codingSchemeDesignator:codeMeaning:)``
///   says otherwise.
///
/// Reference: PS3.3 A.45 - Encapsulated PDF IOD
/// Reference: PS3.3 A.45.2 - Encapsulated CDA IOD
/// Reference: PS3.3 A.85 - Encapsulated STL / OBJ / MTL IODs
/// Reference: PS3.3 C.24 - Encapsulated Document Module
public final class EncapsulatedDocumentBuilder {

    // MARK: - Required Configuration

    private let documentData: Data
    private let mimeType: String
    private let documentType: EncapsulatedDocumentType
    private let studyInstanceUID: String
    private let seriesInstanceUID: String

    // MARK: - Optional Metadata

    private var sopInstanceUID: String?
    private var instanceNumber: Int?
    private var patientName: String?
    private var patientID: String?
    private var documentTitle: String?
    private var modality: String?
    private var seriesDescription: String?
    private var seriesNumber: Int?
    private var contentDate: DICOMDate?
    private var contentTime: DICOMTime?
    private var conceptNameCode: ConceptNameCode?
    private var hl7InstanceIdentifier: String?
    private var sourceInstances: [SourceInstanceReference] = []

    // MARK: - Module attributes carried by the builder only

    private var patientBirthDate: DICOMDate?
    private var patientSex: String?
    private var studyDate: DICOMDate?
    private var studyTime: DICOMTime?
    private var referringPhysicianName: String?
    private var studyID: String?
    private var accessionNumber: String?
    private var manufacturer: String?
    private var manufacturerModelName: String?
    private var deviceSerialNumber: String?
    private var softwareVersions: [String]?
    private var conversionType: String?
    private var burnedInAnnotation: Bool?
    private var acquisitionDateTime: DICOMDateTime?
    private var frameOfReferenceUID: String?
    private var positionReferenceIndicator: String?
    private var measurementUnits: ConceptNameCode?

    // MARK: - Standard values

    /// Table C.8-24 Conversion Type Defined Terms.
    public static let conversionTypeDefinedTerms = ["DV", "DI", "DF", "WSD", "SD", "SI", "DRW", "SYN"]

    /// Default Conversion Type for a document produced on a workstation (Table C.8-24 WSD).
    public static let defaultConversionType = "WSD"

    /// Table C.7-8b defaults when the caller does not identify the real equipment.
    public static let defaultManufacturer = "DICOMKit"
    public static let defaultManufacturerModelName = "EncapsulatedDocumentBuilder"

    /// CID 7063 Model Scale Units: the default is millimetres.
    public static let defaultMeasurementUnits = ConceptNameCode(
        codeValue: "mm", codingSchemeDesignator: "UCUM", codeMeaning: "mm")

    // MARK: - Initialization

    /// Creates a new EncapsulatedDocumentBuilder
    ///
    /// - Parameters:
    ///   - documentData: The raw document data (e.g., PDF file contents)
    ///   - mimeType: The MIME type of the document (e.g., "application/pdf")
    ///   - documentType: The type of encapsulated document
    ///   - studyInstanceUID: The Study Instance UID
    ///   - seriesInstanceUID: The Series Instance UID
    public init(
        documentData: Data,
        mimeType: String,
        documentType: EncapsulatedDocumentType,
        studyInstanceUID: String,
        seriesInstanceUID: String
    ) {
        self.documentData = documentData
        self.mimeType = mimeType
        self.documentType = documentType
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

    /// Sets the Instance Number (Table C.24-2, Type 1; defaults to 1)
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

    /// Sets Patient's Birth Date (0010,0030) (Table C.7-1, Type 2)
    @discardableResult
    public func setPatientBirthDate(_ date: DICOMDate) -> Self {
        self.patientBirthDate = date
        return self
    }

    /// Sets Patient's Sex (0010,0040) (Table C.7-1, Type 2; M, F or O)
    @discardableResult
    public func setPatientSex(_ sex: String) -> Self {
        self.patientSex = sex
        return self
    }

    /// Sets Study Date (0008,0020) and Study Time (0008,0030) (Table C.7-3, Type 2)
    @discardableResult
    public func setStudyDateTime(date: DICOMDate, time: DICOMTime) -> Self {
        self.studyDate = date
        self.studyTime = time
        return self
    }

    /// Sets Referring Physician's Name (0008,0090) (Table C.7-3, Type 2)
    @discardableResult
    public func setReferringPhysicianName(_ name: String) -> Self {
        self.referringPhysicianName = name
        return self
    }

    /// Sets Study ID (0020,0010) (Table C.7-3, Type 2)
    @discardableResult
    public func setStudyID(_ id: String) -> Self {
        self.studyID = id
        return self
    }

    /// Sets Accession Number (0008,0050) (Table C.7-3, Type 2)
    @discardableResult
    public func setAccessionNumber(_ number: String) -> Self {
        self.accessionNumber = number
        return self
    }

    /// Sets the Document Title (Table C.24-2, Type 2)
    @discardableResult
    public func setDocumentTitle(_ title: String) -> Self {
        self.documentTitle = title
        return self
    }

    /// Sets the Modality (Table C.24-1, Type 1). PDF/CDA default to "DOC"; STL/OBJ/MTL
    /// are restricted to the Enumerated Value "M3D" (A.85.1.4.3 / A.85.2.4.3 / A.85.3.4.3).
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

    /// Sets the Series Number (Table C.24-1, Type 1; defaults to 1)
    @discardableResult
    public func setSeriesNumber(_ number: Int) -> Self {
        self.seriesNumber = number
        return self
    }

    /// Sets the Content Date (Table C.24-2, Type 2)
    @discardableResult
    public func setContentDate(_ date: DICOMDate) -> Self {
        self.contentDate = date
        return self
    }

    /// Sets the Content Time (Table C.24-2, Type 2)
    @discardableResult
    public func setContentTime(_ time: DICOMTime) -> Self {
        self.contentTime = time
        return self
    }

    /// Sets Acquisition DateTime (0008,002A) (Table C.24-2, Type 2)
    @discardableResult
    public func setAcquisitionDateTime(_ dateTime: DICOMDateTime) -> Self {
        self.acquisitionDateTime = dateTime
        return self
    }

    /// Sets Burned In Annotation (0028,0301) (Table C.24-2, Type 1): whether the
    /// document contains sufficient identification (including as text in a CDA/PDF)
    /// to identify the patient and date. Defaults to YES.
    @discardableResult
    public func setBurnedInAnnotation(_ containsIdentification: Bool) -> Self {
        self.burnedInAnnotation = containsIdentification
        return self
    }

    /// Sets the Concept Name Code Sequence (Table C.24-2, Type 2)
    @discardableResult
    public func setConceptNameCode(codeValue: String, codingSchemeDesignator: String, codeMeaning: String) -> Self {
        self.conceptNameCode = ConceptNameCode(
            codeValue: codeValue,
            codingSchemeDesignator: codingSchemeDesignator,
            codeMeaning: codeMeaning
        )
        return self
    }

    /// Sets the HL7 Instance Identifier (Table C.24-2, Type 1C: required for CDA documents)
    @discardableResult
    public func setHL7InstanceIdentifier(_ identifier: String) -> Self {
        self.hl7InstanceIdentifier = identifier
        return self
    }

    /// Adds a source instance reference (Table C.24-2 Source Instance Sequence, Type 1C:
    /// required if derived from one or more DICOM Instances)
    @discardableResult
    public func addSourceInstance(sopClassUID: String, sopInstanceUID: String) -> Self {
        self.sourceInstances.append(SourceInstanceReference(
            referencedSOPClassUID: sopClassUID,
            referencedSOPInstanceUID: sopInstanceUID
        ))
        return self
    }

    /// Sets the equipment that produced the object: Manufacturer (0008,0070) (Table
    /// C.7-8, Type 2; Table C.7-8b, Type 1), Manufacturer's Model Name (0008,1090),
    /// Device Serial Number (0018,1000) and Software Versions (0018,1020) (Table
    /// C.7-8b, Type 1 for STL/OBJ/MTL).
    @discardableResult
    public func setEquipment(
        manufacturer: String,
        modelName: String? = nil,
        deviceSerialNumber: String? = nil,
        softwareVersions: [String]? = nil
    ) -> Self {
        self.manufacturer = manufacturer
        self.manufacturerModelName = modelName
        self.deviceSerialNumber = deviceSerialNumber
        self.softwareVersions = softwareVersions
        return self
    }

    /// Sets Conversion Type (0008,0064) (Table C.8-24 SC Equipment, Type 1 for PDF/CDA;
    /// one of the Defined Terms in ``conversionTypeDefinedTerms``; defaults to WSD)
    @discardableResult
    public func setConversionType(_ type: String) -> Self {
        self.conversionType = type
        return self
    }

    /// Sets Frame of Reference UID (0020,0052) (Table C.7-6, Type 1 for STL/OBJ) and
    /// Position Reference Indicator (0020,1040) (Type 2)
    @discardableResult
    public func setFrameOfReference(uid: String, positionReferenceIndicator: String? = nil) -> Self {
        self.frameOfReferenceUID = uid
        self.positionReferenceIndicator = positionReferenceIndicator
        return self
    }

    /// Sets Measurement Units Code Sequence (0040,08EA) (Table C.35.1-1 Manufacturing
    /// 3D Model, Type 1 for STL/OBJ/MTL; CID 7063: m, cm, mm, um from UCUM)
    @discardableResult
    public func setMeasurementUnits(codeValue: String, codingSchemeDesignator: String, codeMeaning: String) -> Self {
        self.measurementUnits = ConceptNameCode(
            codeValue: codeValue,
            codingSchemeDesignator: codingSchemeDesignator,
            codeMeaning: codeMeaning
        )
        return self
    }

    // MARK: - Build

    /// Whether this IOD includes the Manufacturing 3D Model, Enhanced General
    /// Equipment and (STL/OBJ) Frame of Reference modules (Tables A.85.x-1).
    private var is3DModel: Bool {
        switch documentType {
        case .stl, .obj, .mtl: return true
        default: return false
        }
    }

    /// The MIME Type of Encapsulated Document Enumerated Value for the IOD, or nil
    /// when the standard does not enumerate one.
    private static func enumeratedMIMEType(for type: EncapsulatedDocumentType) -> String? {
        switch type {
        case .pdf: return "application/pdf"   // A.45.1.4.1
        case .cda: return "text/XML"          // A.45.2.4
        case .stl: return "model/stl"         // A.85.1.4.2
        case .obj: return "model/obj"         // A.85.2.4.2
        case .mtl: return "model/mtl"         // A.85.3.4.2
        case .unknown: return nil
        }
    }

    /// Builds the EncapsulatedDocument, validating the Type 1 attributes and
    /// Enumerated Values of the IOD.
    ///
    /// - Returns: The constructed EncapsulatedDocument
    /// - Throws: DICOMError.parsingFailed when a Type 1 attribute has no value or an
    ///   Enumerated Value is violated
    public func build() throws -> EncapsulatedDocument {
        guard !documentData.isEmpty else {
            throw DICOMError.parsingFailed("Encapsulated Document (0042,0011) is Type 1 (PS3.3 Table C.24-2): document data cannot be empty")
        }

        guard !mimeType.isEmpty else {
            throw DICOMError.parsingFailed("MIME Type of Encapsulated Document (0042,0012) is Type 1 (PS3.3 Table C.24-2): MIME type cannot be empty")
        }

        // MIME types are case-insensitive (RFC 2045), so compare that way but write
        // the Enumerated Value exactly as the standard spells it.
        var resolvedMIME = mimeType
        if let enumerated = Self.enumeratedMIMEType(for: documentType) {
            guard mimeType.caseInsensitiveCompare(enumerated) == .orderedSame else {
                throw DICOMError.parsingFailed(
                    "MIME Type of Encapsulated Document (0042,0012) for \(documentType) must be '\(enumerated)' (PS3.3 Enumerated Value); got '\(mimeType)'")
            }
            resolvedMIME = enumerated
        }

        // Modality: Type 1 (Table C.24-1); M3D is enumerated for STL/OBJ/MTL.
        let resolvedModality: String
        if is3DModel {
            if let modality, !modality.isEmpty, modality != Modality.m3d.rawValue {
                throw DICOMError.parsingFailed(
                    "Modality (0008,0060) for \(documentType) must be 'M3D' (PS3.3 A.85 Enumerated Value); got '\(modality)'")
            }
            resolvedModality = Modality.m3d.rawValue
        } else {
            resolvedModality = (modality?.isEmpty == false ? modality : nil) ?? Modality.doc.rawValue
        }

        // HL7 Instance Identifier: Type 1C, "Required if encapsulated document is a CDA document".
        if documentType == .cda {
            guard let hl7 = hl7InstanceIdentifier, !hl7.isEmpty else {
                throw DICOMError.parsingFailed(
                    "HL7 Instance Identifier (0040,E001) is Type 1C for Encapsulated CDA (PS3.3 Table C.24-2): set it with setHL7InstanceIdentifier(_:)")
            }
        }

        if let conversionType, !Self.conversionTypeDefinedTerms.contains(conversionType) {
            throw DICOMError.parsingFailed(
                "Conversion Type (0008,0064) '\(conversionType)' is not a PS3.3 Table C.8-24 Defined Term (\(Self.conversionTypeDefinedTerms.joined(separator: ", ")))")
        }

        if let manufacturer, manufacturer.isEmpty, is3DModel {
            throw DICOMError.parsingFailed("Manufacturer (0008,0070) is Type 1 for \(documentType) (PS3.3 Table C.7-8b) and cannot be empty")
        }
        if let frameOfReferenceUID, frameOfReferenceUID.isEmpty, is3DModel {
            throw DICOMError.parsingFailed("Frame of Reference UID (0020,0052) is Type 1 for \(documentType) (PS3.3 Table C.7-6) and cannot be empty")
        }

        let instanceUID = sopInstanceUID ?? UIDGenerator.generateSOPInstanceUID().value

        return EncapsulatedDocument(
            sopInstanceUID: instanceUID,
            sopClassUID: documentType.sopClassUID,
            studyInstanceUID: studyInstanceUID,
            seriesInstanceUID: seriesInstanceUID,
            instanceNumber: instanceNumber ?? 1,
            patientName: patientName,
            patientID: patientID,
            mimeType: resolvedMIME,
            documentTitle: documentTitle,
            documentData: documentData,
            modality: resolvedModality,
            seriesDescription: seriesDescription,
            seriesNumber: seriesNumber ?? 1,
            contentDate: contentDate,
            contentTime: contentTime,
            conceptNameCode: conceptNameCode,
            hl7InstanceIdentifier: hl7InstanceIdentifier,
            sourceInstances: sourceInstances
        )
    }

    /// Builds the EncapsulatedDocument and converts it to a DICOM DataSet carrying
    /// every Type 1 and Type 2 attribute of the IOD's Mandatory modules.
    ///
    /// - Returns: A DataSet ready for DICOM file creation
    /// - Throws: DICOMError if building fails
    public func buildDataSet() throws -> DataSet {
        let document = try build()
        var dataSet = document.toDataSet()

        // Patient Module, Table C.7-1 (Type 2 rows beyond name/ID).
        dataSet.setString(patientBirthDate?.dicomString ?? "", for: .patientBirthDate, vr: .DA)
        dataSet.setString(patientSex ?? "", for: .patientSex, vr: .CS)

        // General Study Module, Table C.7-3 (Type 2 rows).
        dataSet.setString(studyDate?.dicomString ?? "", for: .studyDate, vr: .DA)
        dataSet.setString(studyTime?.dicomString ?? "", for: .studyTime, vr: .TM)
        dataSet.setString(referringPhysicianName ?? "", for: .referringPhysicianName, vr: .PN)
        dataSet.setString(studyID ?? "", for: .studyID, vr: .SH)
        dataSet.setString(accessionNumber ?? "", for: .accessionNumber, vr: .SH)

        // Encapsulated Document Module, Table C.24-2.
        dataSet.setString(acquisitionDateTime?.dicomString ?? "", for: .acquisitionDateTime, vr: .DT)
        dataSet.setString((burnedInAnnotation ?? true) ? "YES" : "NO", for: .burnedInAnnotation, vr: .CS)

        if is3DModel {
            // Enhanced General Equipment Module, Table C.7-8b (all Type 1).
            dataSet.setString(manufacturer ?? Self.defaultManufacturer, for: .manufacturer, vr: .LO)
            dataSet.setString(manufacturerModelName ?? Self.defaultManufacturerModelName,
                              for: .manufacturerModelName, vr: .LO)
            dataSet.setString(deviceSerialNumber ?? DICOMFile.implementationClassUID,
                              for: .deviceSerialNumber, vr: .LO)
            dataSet.setStrings(softwareVersions ?? ["DICOMKit \(version)"], for: .softwareVersions, vr: .LO)

            // Frame of Reference Module, Table C.7-6 (M for STL and OBJ; not in A.85.3-1 MTL).
            if documentType != .mtl {
                dataSet.setString(frameOfReferenceUID ?? UIDGenerator.generateUID().value,
                                  for: .frameOfReferenceUID, vr: .UI)
                dataSet.setString(positionReferenceIndicator ?? "", for: .positionReferenceIndicator, vr: .LO)
            }

            // Manufacturing 3D Model Module, Table C.35.1-1: Measurement Units Code
            // Sequence Type 1, a single Item from CID 7063.
            let units = measurementUnits ?? Self.defaultMeasurementUnits
            dataSet.setSequence([document.makeCodeSequenceItem(units)], for: .measurementUnitsCodeSequence)
        } else {
            // General Equipment Module, Table C.7-8: Manufacturer Type 2.
            dataSet.setString(manufacturer ?? "", for: .manufacturer, vr: .LO)
            if let modelName = manufacturerModelName {
                dataSet.setString(modelName, for: .manufacturerModelName, vr: .LO)
            }
            if let serial = deviceSerialNumber {
                dataSet.setString(serial, for: .deviceSerialNumber, vr: .LO)
            }
            if let versions = softwareVersions {
                dataSet.setStrings(versions, for: .softwareVersions, vr: .LO)
            }
            // SC Equipment Module, Table C.8-24: Conversion Type Type 1.
            dataSet.setString(conversionType ?? Self.defaultConversionType, for: .conversionType, vr: .CS)
        }

        // Specific Character Set: the rows added here may hold non-ASCII text too.
        dataSet.setUTF8SpecificCharacterSetIfNeeded()

        return dataSet
    }
}

// MARK: - DataSet Conversion

extension EncapsulatedDocument {

    /// Converts the EncapsulatedDocument to a DICOM DataSet
    ///
    /// Writes the attributes the document carries plus every Type 1 / Type 2
    /// attribute of the Encapsulated Document Series (Table C.24-1), Encapsulated
    /// Document (Table C.24-2), Patient (Table C.7-1, name and ID), General Study
    /// (Table C.7-3, Study Instance UID), General Equipment (Table C.7-8) and SOP
    /// Common (Table C.12-1) modules, empty where the value is unknown (PS3.5 7.4.3).
    /// Type 1 attributes the document does not carry take the defaults documented on
    /// ``EncapsulatedDocumentBuilder``. `EncapsulatedDocumentBuilder.buildDataSet()`
    /// completes the remaining modules of the IOD.
    ///
    /// - Returns: A DataSet representation of this document
    public func toDataSet() -> DataSet {
        var dataSet = DataSet()

        // SOP Common Module, Table C.12-1 (Type 1).
        dataSet.setString(sopClassUID, for: .sopClassUID, vr: .UI)
        dataSet.setString(sopInstanceUID, for: .sopInstanceUID, vr: .UI)

        // Patient Module, Table C.7-1 (Type 2: present, empty when unknown).
        dataSet.setString(patientName ?? "", for: .patientName, vr: .PN)
        dataSet.setString(patientID ?? "", for: .patientID, vr: .LO)
        dataSet.setString("", for: .patientBirthDate, vr: .DA)
        dataSet.setString("", for: .patientSex, vr: .CS)

        // General Study Module, Table C.7-3.
        dataSet.setString(studyInstanceUID, for: .studyInstanceUID, vr: .UI)
        dataSet.setString("", for: .studyDate, vr: .DA)
        dataSet.setString("", for: .studyTime, vr: .TM)
        dataSet.setString("", for: .referringPhysicianName, vr: .PN)
        dataSet.setString("", for: .studyID, vr: .SH)
        dataSet.setString("", for: .accessionNumber, vr: .SH)

        // Encapsulated Document Series Module, Table C.24-1 (Modality 1, Series
        // Instance UID 1, Series Number 1).
        dataSet.setString(seriesInstanceUID, for: .seriesInstanceUID, vr: .UI)
        let is3DModel = documentType == .stl || documentType == .obj || documentType == .mtl
        let defaultModality = is3DModel ? Modality.m3d.rawValue : Modality.doc.rawValue
        dataSet.setString(modality ?? defaultModality, for: .modality, vr: .CS)
        dataSet.setString(String(seriesNumber ?? 1), for: .seriesNumber, vr: .IS)
        if let seriesDescription = seriesDescription {
            dataSet.setString(seriesDescription, for: .seriesDescription, vr: .LO)
        }

        // General Equipment Module, Table C.7-8 (Manufacturer Type 2).
        dataSet.setString("", for: .manufacturer, vr: .LO)

        // Encapsulated Document Module, Table C.24-2.
        dataSet.setString(String(instanceNumber ?? 1), for: .instanceNumber, vr: .IS)        // Type 1
        dataSet.setString(contentDate?.dicomString ?? "", for: .contentDate, vr: .DA)      // Type 2
        dataSet.setString(contentTime?.dicomString ?? "", for: .contentTime, vr: .TM)      // Type 2
        dataSet.setString("", for: .acquisitionDateTime, vr: .DT)                          // Type 2
        dataSet.setString("YES", for: .burnedInAnnotation, vr: .CS)                        // Type 1
        dataSet.setString(documentTitle ?? "", for: .documentTitle, vr: .ST)               // Type 2
        dataSet.setString(mimeType, for: .mimeTypeOfEncapsulatedDocument, vr: .LO)         // Type 1

        // Document data as OB (Type 1); DICOMWriter pads an odd length with 0x00.
        dataSet[.encapsulatedDocument] = DataElement.data(
            tag: .encapsulatedDocument,
            vr: .OB,
            data: documentData
        )
        // Encapsulated Document Length (Type 3): "the length of the Encapsulated
        // Document stream, not including any trailing padding" (Table C.24-2), so a
        // reader can drop the padding byte of an odd-length document.
        dataSet[EncapsulatedDocumentParser.encapsulatedDocumentLengthTag] = DataElement.uint32(
            tag: EncapsulatedDocumentParser.encapsulatedDocumentLengthTag,
            value: UInt32(clamping: documentData.count))

        // Concept Name Code Sequence (Type 2: "Zero or one Item shall be included")
        if let conceptNameCode = conceptNameCode {
            dataSet.setSequence([makeCodeSequenceItem(conceptNameCode)], for: .conceptNameCodeSequence)
        } else {
            dataSet.setSequence([], for: .conceptNameCodeSequence)
        }

        // HL7 Instance Identifier (Type 1C, CDA)
        if let hl7InstanceIdentifier = hl7InstanceIdentifier {
            dataSet.setString(hl7InstanceIdentifier, for: .hl7InstanceIdentifier, vr: .ST)
        }

        // Source Instance Sequence (Type 1C: required if derived from DICOM Instances)
        if !sourceInstances.isEmpty {
            let items = sourceInstances.map { ref -> SequenceItem in
                var itemElements: [DataElement] = []
                itemElements.append(DataElement.string(
                    tag: .referencedSOPClassUID,
                    vr: .UI,
                    value: ref.referencedSOPClassUID
                ))
                itemElements.append(DataElement.string(
                    tag: .referencedSOPInstanceUID,
                    vr: .UI,
                    value: ref.referencedSOPInstanceUID
                ))
                return SequenceItem(elements: itemElements)
            }
            dataSet.setSequence(items, for: .sourceInstanceSequence)
        }

        // Text is written as UTF-8: Specific Character Set (0008,0005) is Type 1C,
        // required when a value is not ASCII (Table C.12-1; ISO_IR 192, Table C.12-5).
        dataSet.setUTF8SpecificCharacterSetIfNeeded()

        return dataSet
    }

    /// Creates a Code Sequence Item (PS3.3 Table 8.8-1: Code Value SH, Coding Scheme
    /// Designator SH, Code Meaning LO) for a coded concept
    func makeCodeSequenceItem(_ code: ConceptNameCode) -> SequenceItem {
        var elements: [DataElement] = []
        elements.append(DataElement.string(tag: .codeValue, vr: .SH, value: code.codeValue))
        elements.append(DataElement.string(tag: .codingSchemeDesignator, vr: .SH, value: code.codingSchemeDesignator))
        elements.append(DataElement.string(tag: .codeMeaning, vr: .LO, value: code.codeMeaning))
        return SequenceItem(elements: elements)
    }
}
