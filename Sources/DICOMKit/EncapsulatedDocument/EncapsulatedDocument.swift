// NEMA-verified: 2026a, checked 2026-09-29 — SOP Class UIDs match PS3.6 2026a Table A-1; MIME types are the Enumerated Values of PS3.3 A.85 (model/stl)
//
// EncapsulatedDocument.swift
// DICOMKit
//
// Created by DICOMKit on 2026-02-06.
// Copyright © 2026 DICOMKit. All rights reserved.
//

import Foundation
import DICOMCore

/// Represents a DICOM Encapsulated Document IOD
///
/// Encapsulated Documents allow non-DICOM documents (such as PDF files or HL7 CDA documents)
/// to be stored and transmitted using DICOM infrastructure. This enables clinical reports,
/// scanned documents, and structured clinical documents to be managed alongside imaging data.
///
/// Supported SOP Classes:
/// - Encapsulated PDF Storage (1.2.840.10008.5.1.4.1.1.104.1)
/// - Encapsulated CDA Storage (1.2.840.10008.5.1.4.1.1.104.2)
/// - Encapsulated STL Storage (1.2.840.10008.5.1.4.1.1.104.3)
/// - Encapsulated OBJ Storage (1.2.840.10008.5.1.4.1.1.104.4)
/// - Encapsulated MTL Storage (1.2.840.10008.5.1.4.1.1.104.5)
///
/// Reference: PS3.3 A.45 - Encapsulated PDF IOD
/// Reference: PS3.3 A.45.2 - Encapsulated CDA IOD
/// Reference: PS3.3 C.24 - Encapsulated Document Module
public struct EncapsulatedDocument: Sendable {

    // MARK: - SOP Class UIDs

    /// Encapsulated PDF Storage SOP Class UID
    public static let encapsulatedPDFStorageUID = "1.2.840.10008.5.1.4.1.1.104.1"

    /// Encapsulated CDA Storage SOP Class UID
    public static let encapsulatedCDAStorageUID = "1.2.840.10008.5.1.4.1.1.104.2"

    /// Encapsulated STL Storage SOP Class UID
    public static let encapsulatedSTLStorageUID = "1.2.840.10008.5.1.4.1.1.104.3"

    /// Encapsulated OBJ Storage SOP Class UID
    public static let encapsulatedOBJStorageUID = "1.2.840.10008.5.1.4.1.1.104.4"

    /// Encapsulated MTL Storage SOP Class UID
    public static let encapsulatedMTLStorageUID = "1.2.840.10008.5.1.4.1.1.104.5"

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

    // MARK: - Document Information

    /// MIME Type of the encapsulated document (e.g., "application/pdf")
    public let mimeType: String

    /// Document Title
    public let documentTitle: String?

    /// The encapsulated document data
    public let documentData: Data

    // MARK: - Series Information

    /// Modality (typically "DOC" for documents, "OT" for other)
    public let modality: String?

    /// Series Description
    public let seriesDescription: String?

    /// Series Number
    public let seriesNumber: Int?

    // MARK: - Content Date/Time

    /// Content Date
    public let contentDate: DICOMDate?

    /// Content Time
    public let contentTime: DICOMTime?

    // MARK: - Additional Metadata

    /// Concept Name Code Sequence - coded description of the document content
    public let conceptNameCode: ConceptNameCode?

    /// HL7 Instance Identifier for CDA documents
    public let hl7InstanceIdentifier: String?

    /// Source Instance references
    public let sourceInstances: [SourceInstanceReference]

    // MARK: - Initialization

    /// Creates an EncapsulatedDocument
    public init(
        sopInstanceUID: String,
        sopClassUID: String,
        studyInstanceUID: String,
        seriesInstanceUID: String,
        instanceNumber: Int? = nil,
        patientName: String? = nil,
        patientID: String? = nil,
        mimeType: String,
        documentTitle: String? = nil,
        documentData: Data,
        modality: String? = nil,
        seriesDescription: String? = nil,
        seriesNumber: Int? = nil,
        contentDate: DICOMDate? = nil,
        contentTime: DICOMTime? = nil,
        conceptNameCode: ConceptNameCode? = nil,
        hl7InstanceIdentifier: String? = nil,
        sourceInstances: [SourceInstanceReference] = []
    ) {
        self.sopInstanceUID = sopInstanceUID
        self.sopClassUID = sopClassUID
        self.studyInstanceUID = studyInstanceUID
        self.seriesInstanceUID = seriesInstanceUID
        self.instanceNumber = instanceNumber
        self.patientName = patientName
        self.patientID = patientID
        self.mimeType = mimeType
        self.documentTitle = documentTitle
        self.documentData = documentData
        self.modality = modality
        self.seriesDescription = seriesDescription
        self.seriesNumber = seriesNumber
        self.contentDate = contentDate
        self.contentTime = contentTime
        self.conceptNameCode = conceptNameCode
        self.hl7InstanceIdentifier = hl7InstanceIdentifier
        self.sourceInstances = sourceInstances
    }

    /// The document type inferred from the SOP Class UID
    public var documentType: EncapsulatedDocumentType {
        return EncapsulatedDocumentType(sopClassUID: sopClassUID)
    }

    /// The size of the encapsulated document in bytes
    public var documentSize: Int {
        return documentData.count
    }

    /// Whether this is a PDF document
    public var isPDF: Bool {
        return sopClassUID == Self.encapsulatedPDFStorageUID
    }

    /// Whether this is a CDA document
    public var isCDA: Bool {
        return sopClassUID == Self.encapsulatedCDAStorageUID
    }
}

// MARK: - Encapsulated Document Type

/// Type of encapsulated document based on SOP Class UID
public enum EncapsulatedDocumentType: String, Sendable {
    case pdf
    case cda
    case stl
    case obj
    case mtl
    case unknown

    /// Creates a document type from a SOP Class UID
    public init(sopClassUID: String) {
        switch sopClassUID {
        case EncapsulatedDocument.encapsulatedPDFStorageUID:
            self = .pdf
        case EncapsulatedDocument.encapsulatedCDAStorageUID:
            self = .cda
        case EncapsulatedDocument.encapsulatedSTLStorageUID:
            self = .stl
        case EncapsulatedDocument.encapsulatedOBJStorageUID:
            self = .obj
        case EncapsulatedDocument.encapsulatedMTLStorageUID:
            self = .mtl
        default:
            self = .unknown
        }
    }

    /// The expected MIME type for this document type
    public var expectedMIMEType: String {
        switch self {
        case .pdf: return "application/pdf"
        case .cda: return "text/xml"
        case .stl: return "model/stl"   // PS3.3 A.85.1, Enumerated Value of MIME Type of Encapsulated Document
        case .obj: return "model/obj"
        case .mtl: return "model/mtl"
        case .unknown: return "application/octet-stream"
        }
    }

    /// The SOP Class UID for this document type
    public var sopClassUID: String {
        switch self {
        case .pdf: return EncapsulatedDocument.encapsulatedPDFStorageUID
        case .cda: return EncapsulatedDocument.encapsulatedCDAStorageUID
        case .stl: return EncapsulatedDocument.encapsulatedSTLStorageUID
        case .obj: return EncapsulatedDocument.encapsulatedOBJStorageUID
        case .mtl: return EncapsulatedDocument.encapsulatedMTLStorageUID
        case .unknown: return ""
        }
    }
}

// MARK: - Concept Name Code

/// Coded concept for document content description
public struct ConceptNameCode: Sendable {
    /// Code Value
    public let codeValue: String

    /// Coding Scheme Designator
    public let codingSchemeDesignator: String

    /// Code Meaning (human-readable)
    public let codeMeaning: String

    public init(codeValue: String, codingSchemeDesignator: String, codeMeaning: String) {
        self.codeValue = codeValue
        self.codingSchemeDesignator = codingSchemeDesignator
        self.codeMeaning = codeMeaning
    }
}

// MARK: - Source Instance Reference

/// Reference to a source DICOM instance
public struct SourceInstanceReference: Sendable {
    /// Referenced SOP Class UID
    public let referencedSOPClassUID: String

    /// Referenced SOP Instance UID
    public let referencedSOPInstanceUID: String

    public init(referencedSOPClassUID: String, referencedSOPInstanceUID: String) {
        self.referencedSOPClassUID = referencedSOPClassUID
        self.referencedSOPInstanceUID = referencedSOPInstanceUID
    }
}
