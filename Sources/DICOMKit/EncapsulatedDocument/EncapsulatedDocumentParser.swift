// NEMA-verified: 2026a, checked 2026-10-01 — Encapsulated Document module reads per PS3.3 2026a C.24.2; the document is cut to Encapsulated Document Length (0042,0015) "not including any trailing padding" (Table C.24-2) (D181)
//
// EncapsulatedDocumentParser.swift
// DICOMKit
//
// Created by DICOMKit on 2026-02-06.
// Copyright © 2026 DICOMKit. All rights reserved.
//

import Foundation
import DICOMCore

/// Parser for DICOM Encapsulated Document objects
///
/// Parses Encapsulated Document IODs from DICOM data sets, extracting the embedded
/// document data (PDF, CDA, STL, etc.) and associated metadata.
///
/// Reference: PS3.3 A.45 - Encapsulated PDF IOD
/// Reference: PS3.3 A.45.2 - Encapsulated CDA IOD
/// Reference: PS3.3 C.24 - Encapsulated Document Module
public struct EncapsulatedDocumentParser {

    /// Parse an Encapsulated Document from a DICOM data set
    ///
    /// - Parameter dataSet: DICOM data set containing an Encapsulated Document
    /// - Returns: Parsed EncapsulatedDocument
    /// - Throws: DICOMError if parsing fails
    public static func parse(from dataSet: DataSet) throws -> EncapsulatedDocument {
        // Parse SOP Instance UID (required)
        guard let sopInstanceUID = dataSet.string(for: .sopInstanceUID) else {
            throw DICOMError.parsingFailed("Missing SOP Instance UID")
        }

        let sopClassUID = dataSet.string(for: .sopClassUID) ?? EncapsulatedDocument.encapsulatedPDFStorageUID

        // Parse Study and Series UIDs (required)
        guard let studyInstanceUID = dataSet.string(for: .studyInstanceUID) else {
            throw DICOMError.parsingFailed("Missing Study Instance UID")
        }

        guard let seriesInstanceUID = dataSet.string(for: .seriesInstanceUID) else {
            throw DICOMError.parsingFailed("Missing Series Instance UID")
        }

        // Parse MIME Type (required for Encapsulated Document Module)
        guard let mimeType = dataSet.string(for: .mimeTypeOfEncapsulatedDocument) else {
            throw DICOMError.parsingFailed("Missing MIME Type of Encapsulated Document")
        }

        // Parse Encapsulated Document data (required)
        guard let documentElement = dataSet[.encapsulatedDocument] else {
            throw DICOMError.parsingFailed("Missing or empty Encapsulated Document data")
        }
        let documentData = documentStream(documentElement.valueData, in: dataSet)
        guard !documentData.isEmpty else {
            throw DICOMError.parsingFailed("Missing or empty Encapsulated Document data")
        }

        // Parse optional identification
        let instanceNumber = dataSet[.instanceNumber]?.integerStringValue?.value

        // Parse optional patient information
        let patientName = dataSet.string(for: .patientName)
        let patientID = dataSet.string(for: .patientID)

        // Parse optional document metadata
        let documentTitle = dataSet.string(for: .documentTitle)

        // Parse optional series information
        let modality = dataSet.string(for: .modality)
        let seriesDescription = dataSet.string(for: .seriesDescription)
        let seriesNumber: Int?
        if let seriesNumElement = dataSet[.seriesNumber]?.integerStringValue {
            seriesNumber = seriesNumElement.value
        } else {
            seriesNumber = nil
        }

        // Parse content date/time
        let contentDate = dataSet.date(for: .contentDate)
        let contentTime = dataSet.time(for: .contentTime)

        // Parse Concept Name Code Sequence
        let conceptNameCode = parseConceptNameCode(from: dataSet)

        // Parse HL7 Instance Identifier
        let hl7InstanceIdentifier = dataSet.string(for: .hl7InstanceIdentifier)

        // Parse Source Instance Sequence
        let sourceInstances = parseSourceInstances(from: dataSet)

        return EncapsulatedDocument(
            sopInstanceUID: sopInstanceUID,
            sopClassUID: sopClassUID,
            studyInstanceUID: studyInstanceUID,
            seriesInstanceUID: seriesInstanceUID,
            instanceNumber: instanceNumber,
            patientName: patientName,
            patientID: patientID,
            mimeType: mimeType,
            documentTitle: documentTitle,
            documentData: documentData,
            modality: modality,
            seriesDescription: seriesDescription,
            seriesNumber: seriesNumber,
            contentDate: contentDate,
            contentTime: contentTime,
            conceptNameCode: conceptNameCode,
            hl7InstanceIdentifier: hl7InstanceIdentifier,
            sourceInstances: sourceInstances
        )
    }

    /// Encapsulated Document Length (0042,0015), UL (PS3.6 2026a Table 6-1).
    static let encapsulatedDocumentLengthTag = Tag(group: 0x0042, element: 0x0015)

    /// The document stream without the padding byte DICOM adds to an odd-length value:
    /// Encapsulated Document Length (0042,0015) is "the length of the Encapsulated
    /// Document stream, not including any trailing padding added for encapsulation as a
    /// DICOM object. If present, shall be equal to the Value Length if even, or one less
    /// than the Value Length if odd" (PS3.3 2026a Table C.24-2). Without it (Type 3) the
    /// value is returned as stored; a length that is neither the value length nor one
    /// less is ignored.
    public static func documentStream(_ value: Data, in dataSet: DataSet) -> Data {
        guard let length = dataSet.uint32(for: encapsulatedDocumentLengthTag).map(Int.init),
              length == value.count - 1 else { return value }
        return value.prefix(length)
    }

    // MARK: - Private Helpers

    /// Parse Concept Name Code Sequence
    private static func parseConceptNameCode(from dataSet: DataSet) -> ConceptNameCode? {
        guard let items = dataSet.sequence(for: .conceptNameCodeSequence),
              let firstItem = items.first else {
            return nil
        }

        guard let codeValue = firstItem.elements[.codeValue]?.stringValue,
              let codingSchemeDesignator = firstItem.elements[.codingSchemeDesignator]?.stringValue,
              let codeMeaning = firstItem.elements[.codeMeaning]?.stringValue else {
            return nil
        }

        return ConceptNameCode(
            codeValue: codeValue,
            codingSchemeDesignator: codingSchemeDesignator,
            codeMeaning: codeMeaning
        )
    }

    /// Parse Source Instance Sequence
    private static func parseSourceInstances(from dataSet: DataSet) -> [SourceInstanceReference] {
        guard let items = dataSet.sequence(for: .sourceInstanceSequence) else {
            return []
        }

        return items.compactMap { item in
            guard let sopClassUID = item.elements[.referencedSOPClassUID]?.stringValue,
                  let sopInstanceUID = item.elements[.referencedSOPInstanceUID]?.stringValue else {
                return nil
            }
            return SourceInstanceReference(
                referencedSOPClassUID: sopClassUID,
                referencedSOPInstanceUID: sopInstanceUID
            )
        }
    }
}
