//
// EncapsulatedDocumentTests.swift
// DICOMKit
//
// Created by DICOMKit on 2026-02-06.
// Copyright © 2026 DICOMKit. All rights reserved.
//

import XCTest
import DICOMCore
@testable import DICOMKit

final class EncapsulatedDocumentTests: XCTestCase {

    // MARK: - EncapsulatedDocumentType Tests

    func test_documentType_pdf_fromSOPClassUID() {
        let type = EncapsulatedDocumentType(sopClassUID: "1.2.840.10008.5.1.4.1.1.104.1")
        XCTAssertEqual(type, .pdf)
        XCTAssertEqual(type.expectedMIMEType, "application/pdf")
        XCTAssertEqual(type.sopClassUID, "1.2.840.10008.5.1.4.1.1.104.1")
    }

    func test_documentType_cda_fromSOPClassUID() {
        let type = EncapsulatedDocumentType(sopClassUID: "1.2.840.10008.5.1.4.1.1.104.2")
        XCTAssertEqual(type, .cda)
        XCTAssertEqual(type.expectedMIMEType, "text/xml")
    }

    func test_documentType_stl_fromSOPClassUID() {
        let type = EncapsulatedDocumentType(sopClassUID: "1.2.840.10008.5.1.4.1.1.104.3")
        XCTAssertEqual(type, .stl)
        XCTAssertEqual(type.expectedMIMEType, "model/stl")   // PS3.3 A.85.1 Enumerated Value
    }

    func test_documentType_obj_fromSOPClassUID() {
        let type = EncapsulatedDocumentType(sopClassUID: "1.2.840.10008.5.1.4.1.1.104.4")
        XCTAssertEqual(type, .obj)
        XCTAssertEqual(type.expectedMIMEType, "model/obj")
    }

    func test_documentType_mtl_fromSOPClassUID() {
        let type = EncapsulatedDocumentType(sopClassUID: "1.2.840.10008.5.1.4.1.1.104.5")
        XCTAssertEqual(type, .mtl)
        XCTAssertEqual(type.expectedMIMEType, "model/mtl")
    }

    func test_documentType_unknown_fromInvalidSOPClassUID() {
        let type = EncapsulatedDocumentType(sopClassUID: "1.2.3.4.5")
        XCTAssertEqual(type, .unknown)
        XCTAssertEqual(type.expectedMIMEType, "application/octet-stream")
        XCTAssertEqual(type.sopClassUID, "")
    }

    // MARK: - EncapsulatedDocument Property Tests

    func test_document_isPDF_returnsTrue() {
        let doc = makeDocument(sopClassUID: EncapsulatedDocument.encapsulatedPDFStorageUID)
        XCTAssertTrue(doc.isPDF)
        XCTAssertFalse(doc.isCDA)
        XCTAssertEqual(doc.documentType, .pdf)
    }

    func test_document_isCDA_returnsTrue() {
        let doc = makeDocument(sopClassUID: EncapsulatedDocument.encapsulatedCDAStorageUID)
        XCTAssertTrue(doc.isCDA)
        XCTAssertFalse(doc.isPDF)
        XCTAssertEqual(doc.documentType, .cda)
    }

    func test_document_documentSize_returnsCorrectSize() {
        let data = Data(repeating: 0x25, count: 1024)
        let doc = makeDocument(documentData: data)
        XCTAssertEqual(doc.documentSize, 1024)
    }

    // MARK: - ConceptNameCode Tests

    func test_conceptNameCode_initialization() {
        let code = ConceptNameCode(
            codeValue: "18782-3",
            codingSchemeDesignator: "LN",
            codeMeaning: "Radiology Study observation"
        )
        XCTAssertEqual(code.codeValue, "18782-3")
        XCTAssertEqual(code.codingSchemeDesignator, "LN")
        XCTAssertEqual(code.codeMeaning, "Radiology Study observation")
    }

    // MARK: - SourceInstanceReference Tests

    func test_sourceInstanceReference_initialization() {
        let ref = SourceInstanceReference(
            referencedSOPClassUID: "1.2.840.10008.5.1.4.1.1.2",
            referencedSOPInstanceUID: "1.2.3.4.5.6.7"
        )
        XCTAssertEqual(ref.referencedSOPClassUID, "1.2.840.10008.5.1.4.1.1.2")
        XCTAssertEqual(ref.referencedSOPInstanceUID, "1.2.3.4.5.6.7")
    }

    // MARK: - SOP Class UID Constants Tests

    func test_sopClassUID_constants() {
        XCTAssertEqual(EncapsulatedDocument.encapsulatedPDFStorageUID, "1.2.840.10008.5.1.4.1.1.104.1")
        XCTAssertEqual(EncapsulatedDocument.encapsulatedCDAStorageUID, "1.2.840.10008.5.1.4.1.1.104.2")
        XCTAssertEqual(EncapsulatedDocument.encapsulatedSTLStorageUID, "1.2.840.10008.5.1.4.1.1.104.3")
        XCTAssertEqual(EncapsulatedDocument.encapsulatedOBJStorageUID, "1.2.840.10008.5.1.4.1.1.104.4")
        XCTAssertEqual(EncapsulatedDocument.encapsulatedMTLStorageUID, "1.2.840.10008.5.1.4.1.1.104.5")
    }

    // MARK: - Parser Tests

    func test_parser_parsesMinimalDataSet() throws {
        let dataSet = makeMinimalDataSet()
        let doc = try EncapsulatedDocumentParser.parse(from: dataSet)

        XCTAssertEqual(doc.sopInstanceUID, "1.2.3.4.5")
        XCTAssertEqual(doc.sopClassUID, EncapsulatedDocument.encapsulatedPDFStorageUID)
        XCTAssertEqual(doc.studyInstanceUID, "1.2.3")
        XCTAssertEqual(doc.seriesInstanceUID, "1.2.3.4")
        XCTAssertEqual(doc.mimeType, "application/pdf")
        XCTAssertFalse(doc.documentData.isEmpty)
    }

    func test_parser_parsesFullDataSet() throws {
        let dataSet = makeFullDataSet()
        let doc = try EncapsulatedDocumentParser.parse(from: dataSet)

        XCTAssertEqual(doc.sopInstanceUID, "1.2.3.4.5")
        XCTAssertEqual(doc.studyInstanceUID, "1.2.3")
        XCTAssertEqual(doc.seriesInstanceUID, "1.2.3.4")
        XCTAssertEqual(doc.mimeType, "application/pdf")
        XCTAssertEqual(doc.documentTitle, "Radiology Report")
        XCTAssertEqual(doc.patientName, "Smith^John")
        XCTAssertEqual(doc.patientID, "12345")
        XCTAssertEqual(doc.modality, "DOC")
        XCTAssertEqual(doc.seriesDescription, "Reports")
    }

    func test_parser_failsWithMissingSOPInstanceUID() {
        var dataSet = DataSet()
        dataSet.setString(EncapsulatedDocument.encapsulatedPDFStorageUID, for: .sopClassUID, vr: .UI)
        dataSet.setString("1.2.3", for: .studyInstanceUID, vr: .UI)
        dataSet.setString("1.2.3.4", for: .seriesInstanceUID, vr: .UI)
        dataSet.setString("application/pdf", for: .mimeTypeOfEncapsulatedDocument, vr: .LO)
        dataSet[.encapsulatedDocument] = DataElement.data(tag: .encapsulatedDocument, vr: .OB, data: Data([0x25]))

        XCTAssertThrowsError(try EncapsulatedDocumentParser.parse(from: dataSet))
    }

    func test_parser_failsWithMissingStudyInstanceUID() {
        var dataSet = DataSet()
        dataSet.setString("1.2.3.4.5", for: .sopInstanceUID, vr: .UI)
        dataSet.setString(EncapsulatedDocument.encapsulatedPDFStorageUID, for: .sopClassUID, vr: .UI)
        dataSet.setString("1.2.3.4", for: .seriesInstanceUID, vr: .UI)
        dataSet.setString("application/pdf", for: .mimeTypeOfEncapsulatedDocument, vr: .LO)
        dataSet[.encapsulatedDocument] = DataElement.data(tag: .encapsulatedDocument, vr: .OB, data: Data([0x25]))

        XCTAssertThrowsError(try EncapsulatedDocumentParser.parse(from: dataSet))
    }

    func test_parser_failsWithMissingSeriesInstanceUID() {
        var dataSet = DataSet()
        dataSet.setString("1.2.3.4.5", for: .sopInstanceUID, vr: .UI)
        dataSet.setString(EncapsulatedDocument.encapsulatedPDFStorageUID, for: .sopClassUID, vr: .UI)
        dataSet.setString("1.2.3", for: .studyInstanceUID, vr: .UI)
        dataSet.setString("application/pdf", for: .mimeTypeOfEncapsulatedDocument, vr: .LO)
        dataSet[.encapsulatedDocument] = DataElement.data(tag: .encapsulatedDocument, vr: .OB, data: Data([0x25]))

        XCTAssertThrowsError(try EncapsulatedDocumentParser.parse(from: dataSet))
    }

    func test_parser_failsWithMissingMIMEType() {
        var dataSet = DataSet()
        dataSet.setString("1.2.3.4.5", for: .sopInstanceUID, vr: .UI)
        dataSet.setString(EncapsulatedDocument.encapsulatedPDFStorageUID, for: .sopClassUID, vr: .UI)
        dataSet.setString("1.2.3", for: .studyInstanceUID, vr: .UI)
        dataSet.setString("1.2.3.4", for: .seriesInstanceUID, vr: .UI)
        dataSet[.encapsulatedDocument] = DataElement.data(tag: .encapsulatedDocument, vr: .OB, data: Data([0x25]))

        XCTAssertThrowsError(try EncapsulatedDocumentParser.parse(from: dataSet))
    }

    func test_parser_failsWithMissingDocumentData() {
        var dataSet = DataSet()
        dataSet.setString("1.2.3.4.5", for: .sopInstanceUID, vr: .UI)
        dataSet.setString(EncapsulatedDocument.encapsulatedPDFStorageUID, for: .sopClassUID, vr: .UI)
        dataSet.setString("1.2.3", for: .studyInstanceUID, vr: .UI)
        dataSet.setString("1.2.3.4", for: .seriesInstanceUID, vr: .UI)
        dataSet.setString("application/pdf", for: .mimeTypeOfEncapsulatedDocument, vr: .LO)

        XCTAssertThrowsError(try EncapsulatedDocumentParser.parse(from: dataSet))
    }

    func test_parser_failsWithEmptyDocumentData() {
        var dataSet = DataSet()
        dataSet.setString("1.2.3.4.5", for: .sopInstanceUID, vr: .UI)
        dataSet.setString(EncapsulatedDocument.encapsulatedPDFStorageUID, for: .sopClassUID, vr: .UI)
        dataSet.setString("1.2.3", for: .studyInstanceUID, vr: .UI)
        dataSet.setString("1.2.3.4", for: .seriesInstanceUID, vr: .UI)
        dataSet.setString("application/pdf", for: .mimeTypeOfEncapsulatedDocument, vr: .LO)
        dataSet[.encapsulatedDocument] = DataElement.data(tag: .encapsulatedDocument, vr: .OB, data: Data())

        XCTAssertThrowsError(try EncapsulatedDocumentParser.parse(from: dataSet))
    }

    func test_parser_parsesConceptNameCodeSequence() throws {
        var dataSet = makeMinimalDataSet()

        // Add Concept Name Code Sequence
        let codeItem = SequenceItem(elements: [
            DataElement.string(tag: .codeValue, vr: .SH, value: "18782-3"),
            DataElement.string(tag: .codingSchemeDesignator, vr: .SH, value: "LN"),
            DataElement.string(tag: .codeMeaning, vr: .LO, value: "Radiology Study observation")
        ])
        dataSet.setSequence([codeItem], for: .conceptNameCodeSequence)

        let doc = try EncapsulatedDocumentParser.parse(from: dataSet)
        XCTAssertNotNil(doc.conceptNameCode)
        XCTAssertEqual(doc.conceptNameCode?.codeValue, "18782-3")
        XCTAssertEqual(doc.conceptNameCode?.codingSchemeDesignator, "LN")
        XCTAssertEqual(doc.conceptNameCode?.codeMeaning, "Radiology Study observation")
    }

    func test_parser_parsesSourceInstanceSequence() throws {
        var dataSet = makeMinimalDataSet()

        // Add Source Instance Sequence
        let refItem = SequenceItem(elements: [
            DataElement.string(tag: .referencedSOPClassUID, vr: .UI, value: "1.2.840.10008.5.1.4.1.1.2"),
            DataElement.string(tag: .referencedSOPInstanceUID, vr: .UI, value: "1.2.3.4.5.6.7")
        ])
        dataSet.setSequence([refItem], for: .sourceInstanceSequence)

        let doc = try EncapsulatedDocumentParser.parse(from: dataSet)
        XCTAssertEqual(doc.sourceInstances.count, 1)
        XCTAssertEqual(doc.sourceInstances[0].referencedSOPClassUID, "1.2.840.10008.5.1.4.1.1.2")
        XCTAssertEqual(doc.sourceInstances[0].referencedSOPInstanceUID, "1.2.3.4.5.6.7")
    }

    func test_parser_parsesHL7InstanceIdentifier() throws {
        var dataSet = makeMinimalDataSet()
        dataSet.setString("2.16.840.1.113883.19.999.1", for: .hl7InstanceIdentifier, vr: .ST)

        let doc = try EncapsulatedDocumentParser.parse(from: dataSet)
        XCTAssertEqual(doc.hl7InstanceIdentifier, "2.16.840.1.113883.19.999.1")
    }

    func test_parser_parsesCDADocument() throws {
        var dataSet = DataSet()
        dataSet.setString("1.2.3.4.5.6", for: .sopInstanceUID, vr: .UI)
        dataSet.setString(EncapsulatedDocument.encapsulatedCDAStorageUID, for: .sopClassUID, vr: .UI)
        dataSet.setString("1.2.3", for: .studyInstanceUID, vr: .UI)
        dataSet.setString("1.2.3.4", for: .seriesInstanceUID, vr: .UI)
        dataSet.setString("text/xml", for: .mimeTypeOfEncapsulatedDocument, vr: .LO)
        let cdaData = "<ClinicalDocument/>".data(using: .utf8)!
        dataSet[.encapsulatedDocument] = DataElement.data(tag: .encapsulatedDocument, vr: .OB, data: cdaData)

        let doc = try EncapsulatedDocumentParser.parse(from: dataSet)
        XCTAssertTrue(doc.isCDA)
        XCTAssertEqual(doc.mimeType, "text/xml")
        XCTAssertEqual(doc.documentType, .cda)
    }

    // MARK: - Builder Tests

    func test_builder_buildsMinimalDocument() throws {
        let pdfData = makeSamplePDFData()
        let doc = try EncapsulatedDocumentBuilder(
            documentData: pdfData,
            mimeType: "application/pdf",
            documentType: .pdf,
            studyInstanceUID: "1.2.3",
            seriesInstanceUID: "1.2.3.4"
        ).build()

        XCTAssertFalse(doc.sopInstanceUID.isEmpty)
        XCTAssertEqual(doc.sopClassUID, EncapsulatedDocument.encapsulatedPDFStorageUID)
        XCTAssertEqual(doc.studyInstanceUID, "1.2.3")
        XCTAssertEqual(doc.seriesInstanceUID, "1.2.3.4")
        XCTAssertEqual(doc.mimeType, "application/pdf")
        XCTAssertEqual(doc.documentData, pdfData)
        XCTAssertTrue(doc.isPDF)
    }

    func test_builder_buildsFullDocument() throws {
        let pdfData = makeSamplePDFData()
        let doc = try EncapsulatedDocumentBuilder(
            documentData: pdfData,
            mimeType: "application/pdf",
            documentType: .pdf,
            studyInstanceUID: "1.2.3",
            seriesInstanceUID: "1.2.3.4"
        )
        .setSOPInstanceUID("1.2.3.4.5.99")
        .setInstanceNumber(1)
        .setPatientName("Doe^Jane")
        .setPatientID("67890")
        .setDocumentTitle("Chest X-Ray Report")
        .setModality("DOC")
        .setSeriesDescription("Clinical Reports")
        .setSeriesNumber(1)
        .setConceptNameCode(
            codeValue: "18782-3",
            codingSchemeDesignator: "LN",
            codeMeaning: "Radiology Study observation"
        )
        .addSourceInstance(
            sopClassUID: "1.2.840.10008.5.1.4.1.1.2",
            sopInstanceUID: "1.2.3.4.5.6"
        )
        .build()

        XCTAssertEqual(doc.sopInstanceUID, "1.2.3.4.5.99")
        XCTAssertEqual(doc.instanceNumber, 1)
        XCTAssertEqual(doc.patientName, "Doe^Jane")
        XCTAssertEqual(doc.patientID, "67890")
        XCTAssertEqual(doc.documentTitle, "Chest X-Ray Report")
        XCTAssertEqual(doc.modality, "DOC")
        XCTAssertEqual(doc.seriesDescription, "Clinical Reports")
        XCTAssertEqual(doc.seriesNumber, 1)
        XCTAssertNotNil(doc.conceptNameCode)
        XCTAssertEqual(doc.conceptNameCode?.codeValue, "18782-3")
        XCTAssertEqual(doc.sourceInstances.count, 1)
    }

    func test_builder_failsWithEmptyDocumentData() {
        XCTAssertThrowsError(try EncapsulatedDocumentBuilder(
            documentData: Data(),
            mimeType: "application/pdf",
            documentType: .pdf,
            studyInstanceUID: "1.2.3",
            seriesInstanceUID: "1.2.3.4"
        ).build())
    }

    func test_builder_failsWithEmptyMIMEType() {
        XCTAssertThrowsError(try EncapsulatedDocumentBuilder(
            documentData: Data([0x25]),
            mimeType: "",
            documentType: .pdf,
            studyInstanceUID: "1.2.3",
            seriesInstanceUID: "1.2.3.4"
        ).build())
    }

    func test_builder_buildsCDADocument() throws {
        let cdaData = "<ClinicalDocument/>".data(using: .utf8)!
        let doc = try EncapsulatedDocumentBuilder(
            documentData: cdaData,
            mimeType: "text/xml",
            documentType: .cda,
            studyInstanceUID: "1.2.3",
            seriesInstanceUID: "1.2.3.4"
        )
        .setHL7InstanceIdentifier("2.16.840.1.113883.19.999.1")
        .build()

        XCTAssertTrue(doc.isCDA)
        XCTAssertEqual(doc.hl7InstanceIdentifier, "2.16.840.1.113883.19.999.1")
        XCTAssertEqual(doc.mimeType, "text/XML", "PS3.3 A.45.2.4 Enumerated Value spelling")
    }

    func test_builder_generatesUniqueSOPInstanceUID() throws {
        let data = Data([0x25])
        let doc1 = try EncapsulatedDocumentBuilder(
            documentData: data,
            mimeType: "application/pdf",
            documentType: .pdf,
            studyInstanceUID: "1.2.3",
            seriesInstanceUID: "1.2.3.4"
        ).build()

        let doc2 = try EncapsulatedDocumentBuilder(
            documentData: data,
            mimeType: "application/pdf",
            documentType: .pdf,
            studyInstanceUID: "1.2.3",
            seriesInstanceUID: "1.2.3.4"
        ).build()

        XCTAssertNotEqual(doc1.sopInstanceUID, doc2.sopInstanceUID)
    }

    // MARK: - DataSet Conversion (toDataSet) Tests

    func test_toDataSet_containsRequiredAttributes() throws {
        let pdfData = makeSamplePDFData()
        let doc = try EncapsulatedDocumentBuilder(
            documentData: pdfData,
            mimeType: "application/pdf",
            documentType: .pdf,
            studyInstanceUID: "1.2.3",
            seriesInstanceUID: "1.2.3.4"
        )
        .setSOPInstanceUID("1.2.3.4.5")
        .build()

        let dataSet = doc.toDataSet()

        XCTAssertEqual(dataSet.string(for: .sopClassUID), EncapsulatedDocument.encapsulatedPDFStorageUID)
        XCTAssertEqual(dataSet.string(for: .sopInstanceUID), "1.2.3.4.5")
        XCTAssertEqual(dataSet.string(for: .studyInstanceUID), "1.2.3")
        XCTAssertEqual(dataSet.string(for: .seriesInstanceUID), "1.2.3.4")
        XCTAssertEqual(dataSet.string(for: .mimeTypeOfEncapsulatedDocument), "application/pdf")

        // Check document data element exists
        let docElement = dataSet[.encapsulatedDocument]
        XCTAssertNotNil(docElement)
        XCTAssertFalse(docElement!.valueData.isEmpty)
    }

    func test_toDataSet_containsOptionalAttributes() throws {
        let pdfData = makeSamplePDFData()
        let doc = try EncapsulatedDocumentBuilder(
            documentData: pdfData,
            mimeType: "application/pdf",
            documentType: .pdf,
            studyInstanceUID: "1.2.3",
            seriesInstanceUID: "1.2.3.4"
        )
        .setPatientName("Doe^Jane")
        .setPatientID("12345")
        .setDocumentTitle("Report")
        .setModality("DOC")
        .setSeriesDescription("Reports")
        .build()

        let dataSet = doc.toDataSet()

        XCTAssertEqual(dataSet.string(for: .patientName), "Doe^Jane")
        XCTAssertEqual(dataSet.string(for: .patientID), "12345")
        XCTAssertEqual(dataSet.string(for: .documentTitle), "Report")
        XCTAssertEqual(dataSet.string(for: .modality), "DOC")
        XCTAssertEqual(dataSet.string(for: .seriesDescription), "Reports")
    }

    func test_toDataSet_containsConceptNameCodeSequence() throws {
        let pdfData = makeSamplePDFData()
        let doc = try EncapsulatedDocumentBuilder(
            documentData: pdfData,
            mimeType: "application/pdf",
            documentType: .pdf,
            studyInstanceUID: "1.2.3",
            seriesInstanceUID: "1.2.3.4"
        )
        .setConceptNameCode(
            codeValue: "18782-3",
            codingSchemeDesignator: "LN",
            codeMeaning: "Radiology Study observation"
        )
        .build()

        let dataSet = doc.toDataSet()

        let items = dataSet.sequence(for: .conceptNameCodeSequence)
        XCTAssertNotNil(items)
        XCTAssertEqual(items?.count, 1)
    }

    func test_toDataSet_containsSourceInstanceSequence() throws {
        let pdfData = makeSamplePDFData()
        let doc = try EncapsulatedDocumentBuilder(
            documentData: pdfData,
            mimeType: "application/pdf",
            documentType: .pdf,
            studyInstanceUID: "1.2.3",
            seriesInstanceUID: "1.2.3.4"
        )
        .addSourceInstance(
            sopClassUID: "1.2.840.10008.5.1.4.1.1.2",
            sopInstanceUID: "1.2.3.4.5.6"
        )
        .build()

        let dataSet = doc.toDataSet()

        let items = dataSet.sequence(for: .sourceInstanceSequence)
        XCTAssertNotNil(items)
        XCTAssertEqual(items?.count, 1)
    }

    // MARK: - Round-Trip Tests

    func test_roundTrip_buildParseProducesEquivalentDocument() throws {
        let pdfData = makeSamplePDFData()
        let original = try EncapsulatedDocumentBuilder(
            documentData: pdfData,
            mimeType: "application/pdf",
            documentType: .pdf,
            studyInstanceUID: "1.2.3",
            seriesInstanceUID: "1.2.3.4"
        )
        .setSOPInstanceUID("1.2.3.4.5")
        .setPatientName("Smith^John")
        .setPatientID("12345")
        .setDocumentTitle("Test Report")
        .setModality("DOC")
        .build()

        // Convert to DataSet, then parse back
        let dataSet = original.toDataSet()
        let parsed = try EncapsulatedDocumentParser.parse(from: dataSet)

        XCTAssertEqual(parsed.sopInstanceUID, original.sopInstanceUID)
        XCTAssertEqual(parsed.sopClassUID, original.sopClassUID)
        XCTAssertEqual(parsed.studyInstanceUID, original.studyInstanceUID)
        XCTAssertEqual(parsed.seriesInstanceUID, original.seriesInstanceUID)
        XCTAssertEqual(parsed.mimeType, original.mimeType)
        XCTAssertEqual(parsed.patientName, original.patientName)
        XCTAssertEqual(parsed.patientID, original.patientID)
        XCTAssertEqual(parsed.documentTitle, original.documentTitle)
        XCTAssertEqual(parsed.modality, original.modality)
        // Document data may have padding byte due to DICOM even-length rule
        XCTAssertTrue(parsed.documentData.starts(with: original.documentData))
    }

    func test_roundTrip_cdaDocument() throws {
        let cdaData = "<ClinicalDocument xmlns='urn:hl7-org:v3'></ClinicalDocument>".data(using: .utf8)!
        let original = try EncapsulatedDocumentBuilder(
            documentData: cdaData,
            mimeType: "text/xml",
            documentType: .cda,
            studyInstanceUID: "1.2.3",
            seriesInstanceUID: "1.2.3.4"
        )
        .setSOPInstanceUID("1.2.3.4.5.cda")
        .setHL7InstanceIdentifier("2.16.840.1.113883.19.999.1")
        .build()

        let dataSet = original.toDataSet()
        let parsed = try EncapsulatedDocumentParser.parse(from: dataSet)

        XCTAssertEqual(parsed.sopClassUID, EncapsulatedDocument.encapsulatedCDAStorageUID)
        // PS3.3 A.45.2.4: the Enumerated Value is spelled "text/XML"; the builder
        // normalises the case-insensitive MIME type to it.
        XCTAssertEqual(parsed.mimeType, "text/XML")
        XCTAssertEqual(parsed.hl7InstanceIdentifier, "2.16.840.1.113883.19.999.1")
        XCTAssertTrue(parsed.isCDA)
    }

    func test_roundTrip_withConceptNameCode() throws {
        let pdfData = makeSamplePDFData()
        let original = try EncapsulatedDocumentBuilder(
            documentData: pdfData,
            mimeType: "application/pdf",
            documentType: .pdf,
            studyInstanceUID: "1.2.3",
            seriesInstanceUID: "1.2.3.4"
        )
        .setSOPInstanceUID("1.2.3.4.5.code")
        .setConceptNameCode(
            codeValue: "18782-3",
            codingSchemeDesignator: "LN",
            codeMeaning: "Radiology Study observation"
        )
        .build()

        let dataSet = original.toDataSet()
        let parsed = try EncapsulatedDocumentParser.parse(from: dataSet)

        XCTAssertNotNil(parsed.conceptNameCode)
        XCTAssertEqual(parsed.conceptNameCode?.codeValue, "18782-3")
        XCTAssertEqual(parsed.conceptNameCode?.codingSchemeDesignator, "LN")
        XCTAssertEqual(parsed.conceptNameCode?.codeMeaning, "Radiology Study observation")
    }

    func test_roundTrip_withSourceInstances() throws {
        let pdfData = makeSamplePDFData()
        let original = try EncapsulatedDocumentBuilder(
            documentData: pdfData,
            mimeType: "application/pdf",
            documentType: .pdf,
            studyInstanceUID: "1.2.3",
            seriesInstanceUID: "1.2.3.4"
        )
        .setSOPInstanceUID("1.2.3.4.5.src")
        .addSourceInstance(
            sopClassUID: "1.2.840.10008.5.1.4.1.1.2",
            sopInstanceUID: "1.2.3.4.5.6.7"
        )
        .addSourceInstance(
            sopClassUID: "1.2.840.10008.5.1.4.1.1.4",
            sopInstanceUID: "1.2.3.4.5.6.8"
        )
        .build()

        let dataSet = original.toDataSet()
        let parsed = try EncapsulatedDocumentParser.parse(from: dataSet)

        XCTAssertEqual(parsed.sourceInstances.count, 2)
        XCTAssertEqual(parsed.sourceInstances[0].referencedSOPClassUID, "1.2.840.10008.5.1.4.1.1.2")
        XCTAssertEqual(parsed.sourceInstances[0].referencedSOPInstanceUID, "1.2.3.4.5.6.7")
        XCTAssertEqual(parsed.sourceInstances[1].referencedSOPClassUID, "1.2.840.10008.5.1.4.1.1.4")
        XCTAssertEqual(parsed.sourceInstances[1].referencedSOPInstanceUID, "1.2.3.4.5.6.8")
    }

    // MARK: - BuildDataSet Tests

    func test_builder_buildDataSet() throws {
        let pdfData = makeSamplePDFData()
        let dataSet = try EncapsulatedDocumentBuilder(
            documentData: pdfData,
            mimeType: "application/pdf",
            documentType: .pdf,
            studyInstanceUID: "1.2.3",
            seriesInstanceUID: "1.2.3.4"
        )
        .setDocumentTitle("Direct DataSet Test")
        .buildDataSet()

        XCTAssertEqual(dataSet.string(for: .sopClassUID), EncapsulatedDocument.encapsulatedPDFStorageUID)
        XCTAssertEqual(dataSet.string(for: .mimeTypeOfEncapsulatedDocument), "application/pdf")
        XCTAssertEqual(dataSet.string(for: .documentTitle), "Direct DataSet Test")
    }


    // MARK: - IOD completeness (P-ENCAP): Type 1 / Type 2 of Tables A.45.1-1, A.85.1-1

    private func pdfDataSet(_ configure: (EncapsulatedDocumentBuilder) -> Void = { _ in }) throws -> DataSet {
        let builder = EncapsulatedDocumentBuilder(
            documentData: makeSamplePDFData(),
            mimeType: "application/pdf",
            documentType: .pdf,
            studyInstanceUID: "1.2.3",
            seriesInstanceUID: "1.2.3.4")
        configure(builder)
        return try builder.buildDataSet()
    }

    private func assertPresent(_ ds: DataSet, _ tag: Tag, _ name: String, nonEmpty: Bool, file: StaticString = #filePath, line: UInt = #line) {
        guard let element = ds[tag] else {
            XCTFail("\(name) \(tag) must be present", file: file, line: line); return
        }
        if nonEmpty {
            let empty = element.sequenceItems?.isEmpty ?? (element.length == 0)
            XCTAssertFalse(empty, "\(name) \(tag) is Type 1 and must not be empty", file: file, line: line)
        }
    }

    func test_buildDataSet_pdf_writesEveryType1AndType2Attribute() throws {
        let ds = try pdfDataSet()
        // Table C.7-1 Patient (Type 2)
        for (tag, name) in [(Tag.patientName, "Patient's Name"), (.patientID, "Patient ID"),
                            (.patientBirthDate, "Patient's Birth Date"), (.patientSex, "Patient's Sex")] {
            assertPresent(ds, tag, name, nonEmpty: false)
        }
        // Table C.7-3 General Study
        assertPresent(ds, .studyInstanceUID, "Study Instance UID", nonEmpty: true)
        for (tag, name) in [(Tag.studyDate, "Study Date"), (.studyTime, "Study Time"),
                            (.referringPhysicianName, "Referring Physician's Name"),
                            (.studyID, "Study ID"), (.accessionNumber, "Accession Number")] {
            assertPresent(ds, tag, name, nonEmpty: false)
        }
        // Table C.24-1 Encapsulated Document Series (all Type 1)
        assertPresent(ds, .modality, "Modality", nonEmpty: true)
        XCTAssertEqual(ds.string(for: .modality), "DOC")
        assertPresent(ds, .seriesInstanceUID, "Series Instance UID", nonEmpty: true)
        assertPresent(ds, .seriesNumber, "Series Number", nonEmpty: true)
        // Table C.7-8 General Equipment (Type 2) and Table C.8-24 SC Equipment (Type 1)
        assertPresent(ds, .manufacturer, "Manufacturer", nonEmpty: false)
        assertPresent(ds, .conversionType, "Conversion Type", nonEmpty: true)
        XCTAssertEqual(ds.string(for: .conversionType), "WSD")
        // Table C.24-2 Encapsulated Document
        assertPresent(ds, .instanceNumber, "Instance Number", nonEmpty: true)
        assertPresent(ds, .contentDate, "Content Date", nonEmpty: false)
        assertPresent(ds, .contentTime, "Content Time", nonEmpty: false)
        assertPresent(ds, .acquisitionDateTime, "Acquisition DateTime", nonEmpty: false)
        assertPresent(ds, .burnedInAnnotation, "Burned In Annotation", nonEmpty: true)
        XCTAssertEqual(ds.string(for: .burnedInAnnotation), "YES")
        assertPresent(ds, .documentTitle, "Document Title", nonEmpty: false)
        assertPresent(ds, .conceptNameCodeSequence, "Concept Name Code Sequence", nonEmpty: false)
        XCTAssertEqual(ds[.conceptNameCodeSequence]?.vr, .SQ)
        assertPresent(ds, .mimeTypeOfEncapsulatedDocument, "MIME Type of Encapsulated Document", nonEmpty: true)
        assertPresent(ds, .encapsulatedDocument, "Encapsulated Document", nonEmpty: true)
        // Table C.12-1 SOP Common
        assertPresent(ds, .sopClassUID, "SOP Class UID", nonEmpty: true)
        assertPresent(ds, .sopInstanceUID, "SOP Instance UID", nonEmpty: true)
        // Not part of the PDF IOD
        XCTAssertNil(ds[.frameOfReferenceUID])
        XCTAssertNil(ds[.measurementUnitsCodeSequence])

        // VRs per PS3.6 Table 6-1
        XCTAssertEqual(ds[.acquisitionDateTime]?.vr, .DT)
        XCTAssertEqual(ds[.burnedInAnnotation]?.vr, .CS)
        XCTAssertEqual(ds[.documentTitle]?.vr, .ST)
        XCTAssertEqual(ds[.seriesNumber]?.vr, .IS)
        XCTAssertEqual(ds[.conversionType]?.vr, .CS)
    }

    func test_buildDataSet_pdf_setters() throws {
        let ds = try pdfDataSet {
            $0.setBurnedInAnnotation(false)
             .setConversionType("SD")
             .setPatientSex("F")
             .setEquipment(manufacturer: "ACME", modelName: "Scanner 1")
             .setAcquisitionDateTime(DICOMDateTime(year: 2026, month: 9, day: 29, hour: 12, minute: 0, second: 0))
        }
        XCTAssertEqual(ds.string(for: .burnedInAnnotation), "NO")
        XCTAssertEqual(ds.string(for: .conversionType), "SD")
        XCTAssertEqual(ds.string(for: .patientSex), "F")
        XCTAssertEqual(ds.string(for: .manufacturer), "ACME")
        XCTAssertEqual(ds.string(for: .manufacturerModelName), "Scanner 1")
        XCTAssertEqual(ds.string(for: .acquisitionDateTime)?.hasPrefix("20260929120000"), true)
    }

    func test_build_rejectsInvalidType1Values() {
        // MIME Type of Encapsulated Document Enumerated Value (A.45.1.4.1)
        XCTAssertThrowsError(try EncapsulatedDocumentBuilder(
            documentData: makeSamplePDFData(), mimeType: "image/png", documentType: .pdf,
            studyInstanceUID: "1.2.3", seriesInstanceUID: "1.2.3.4").build())
        // Conversion Type Defined Terms (Table C.8-24)
        XCTAssertThrowsError(try EncapsulatedDocumentBuilder(
            documentData: makeSamplePDFData(), mimeType: "application/pdf", documentType: .pdf,
            studyInstanceUID: "1.2.3", seriesInstanceUID: "1.2.3.4").setConversionType("XYZ").build())
        // HL7 Instance Identifier 1C for CDA (Table C.24-2)
        XCTAssertThrowsError(try EncapsulatedDocumentBuilder(
            documentData: Data("<ClinicalDocument/>".utf8), mimeType: "text/xml", documentType: .cda,
            studyInstanceUID: "1.2.3", seriesInstanceUID: "1.2.3.4").build())
        // Modality Enumerated Value M3D for STL (A.85.1.4.3)
        XCTAssertThrowsError(try EncapsulatedDocumentBuilder(
            documentData: Data(repeating: 0, count: 84), mimeType: "model/stl", documentType: .stl,
            studyInstanceUID: "1.2.3", seriesInstanceUID: "1.2.3.4").setModality("DOC").build())
    }

    func test_buildDataSet_stl_writesEnhancedEquipmentFrameOfReferenceAndUnits() throws {
        let ds = try EncapsulatedDocumentBuilder(
            documentData: Data(repeating: 0, count: 84), mimeType: "model/stl", documentType: .stl,
            studyInstanceUID: "1.2.3", seriesInstanceUID: "1.2.3.4").buildDataSet()

        XCTAssertEqual(ds.string(for: .modality), "M3D")
        XCTAssertEqual(ds.string(for: .mimeTypeOfEncapsulatedDocument), "model/stl")
        // Table C.7-8b Enhanced General Equipment (all Type 1)
        for (tag, name) in [(Tag.manufacturer, "Manufacturer"), (.manufacturerModelName, "Manufacturer's Model Name"),
                            (.deviceSerialNumber, "Device Serial Number"), (.softwareVersions, "Software Versions")] {
            assertPresent(ds, tag, name, nonEmpty: true)
        }
        XCTAssertNil(ds[.conversionType], "SC Equipment is not in Table A.85.1-1")
        // Table C.7-6 Frame of Reference
        assertPresent(ds, .frameOfReferenceUID, "Frame of Reference UID", nonEmpty: true)
        assertPresent(ds, .positionReferenceIndicator, "Position Reference Indicator", nonEmpty: false)
        // Table C.35.1-1 Measurement Units Code Sequence (CID 7063)
        let units = try XCTUnwrap(ds.sequence(for: .measurementUnitsCodeSequence)?.first)
        XCTAssertEqual(units.string(for: .codeValue), "mm")
        XCTAssertEqual(units.string(for: .codingSchemeDesignator), "UCUM")
        XCTAssertEqual(units.string(for: .codeMeaning), "mm")
    }

    func test_buildDataSet_mtl_hasNoFrameOfReference() throws {
        let ds = try EncapsulatedDocumentBuilder(
            documentData: Data("newmtl a\n".utf8), mimeType: "model/mtl", documentType: .mtl,
            studyInstanceUID: "1.2.3", seriesInstanceUID: "1.2.3.4")
            .setEquipment(manufacturer: "ACME", modelName: "M", deviceSerialNumber: "S1", softwareVersions: ["1.0"])
            .setMeasurementUnits(codeValue: "cm", codingSchemeDesignator: "UCUM", codeMeaning: "cm")
            .buildDataSet()
        XCTAssertNil(ds[.frameOfReferenceUID], "Table A.85.3-1 has no Frame of Reference module")
        XCTAssertEqual(ds.string(for: .deviceSerialNumber), "S1")
        XCTAssertEqual(ds.sequence(for: .measurementUnitsCodeSequence)?.first?.string(for: .codeValue), "cm")
    }

    // MARK: - DICOM File Creation Test

    func test_createDICOMFile_withEncapsulatedPDF() throws {
        let pdfData = makeSamplePDFData()
        let dataSet = try EncapsulatedDocumentBuilder(
            documentData: pdfData,
            mimeType: "application/pdf",
            documentType: .pdf,
            studyInstanceUID: "1.2.3",
            seriesInstanceUID: "1.2.3.4"
        )
        .setSOPInstanceUID("1.2.3.4.5.file")
        .buildDataSet()

        let dicomFile = DICOMFile.create(
            dataSet: dataSet,
            sopClassUID: EncapsulatedDocument.encapsulatedPDFStorageUID,
            sopInstanceUID: "1.2.3.4.5.file"
        )

        // Verify the DICOM file has correct meta information
        XCTAssertEqual(
            dicomFile.fileMetaInformation.string(for: .mediaStorageSOPClassUID),
            EncapsulatedDocument.encapsulatedPDFStorageUID
        )

        // Verify it can be serialized
        let fileData = try dicomFile.write()
        XCTAssertFalse(fileData.isEmpty)
        XCTAssertTrue(fileData.count > 132) // At least preamble + prefix
    }

    // MARK: - Tag Tests

    func test_tags_encapsulatedDocument() {
        XCTAssertEqual(Tag.encapsulatedDocument.group, 0x0042)
        XCTAssertEqual(Tag.encapsulatedDocument.element, 0x0011)
    }

    func test_tags_mimeTypeOfEncapsulatedDocument() {
        XCTAssertEqual(Tag.mimeTypeOfEncapsulatedDocument.group, 0x0042)
        XCTAssertEqual(Tag.mimeTypeOfEncapsulatedDocument.element, 0x0012)
    }

    func test_tags_documentTitle() {
        XCTAssertEqual(Tag.documentTitle.group, 0x0042)
        XCTAssertEqual(Tag.documentTitle.element, 0x0010)
    }

    func test_tags_sourceInstanceSequence() {
        XCTAssertEqual(Tag.sourceInstanceSequence.group, 0x0042)
        XCTAssertEqual(Tag.sourceInstanceSequence.element, 0x0013)
    }

    func test_tags_hl7InstanceIdentifier() {
        XCTAssertEqual(Tag.hl7InstanceIdentifier.group, 0x0040)
        XCTAssertEqual(Tag.hl7InstanceIdentifier.element, 0xE001)
    }

    // MARK: - Helpers

    private func makeDocument(
        sopClassUID: String = EncapsulatedDocument.encapsulatedPDFStorageUID,
        documentData: Data = Data([0x25, 0x50, 0x44, 0x46])
    ) -> EncapsulatedDocument {
        EncapsulatedDocument(
            sopInstanceUID: "1.2.3.4.5",
            sopClassUID: sopClassUID,
            studyInstanceUID: "1.2.3",
            seriesInstanceUID: "1.2.3.4",
            mimeType: "application/pdf",
            documentData: documentData
        )
    }

    private func makeSamplePDFData() -> Data {
        // Minimal PDF-like data (starts with %PDF)
        return "%PDF-1.4 test document".data(using: .utf8)!
    }

    private func makeMinimalDataSet() -> DataSet {
        var dataSet = DataSet()
        dataSet.setString("1.2.3.4.5", for: .sopInstanceUID, vr: .UI)
        dataSet.setString(EncapsulatedDocument.encapsulatedPDFStorageUID, for: .sopClassUID, vr: .UI)
        dataSet.setString("1.2.3", for: .studyInstanceUID, vr: .UI)
        dataSet.setString("1.2.3.4", for: .seriesInstanceUID, vr: .UI)
        dataSet.setString("application/pdf", for: .mimeTypeOfEncapsulatedDocument, vr: .LO)
        let pdfData = makeSamplePDFData()
        dataSet[.encapsulatedDocument] = DataElement.data(tag: .encapsulatedDocument, vr: .OB, data: pdfData)
        return dataSet
    }

    private func makeFullDataSet() -> DataSet {
        var dataSet = makeMinimalDataSet()
        dataSet.setString("Smith^John", for: .patientName, vr: .PN)
        dataSet.setString("12345", for: .patientID, vr: .LO)
        dataSet.setString("Radiology Report", for: .documentTitle, vr: .ST)
        dataSet.setString("DOC", for: .modality, vr: .CS)
        dataSet.setString("Reports", for: .seriesDescription, vr: .LO)
        return dataSet
    }
}

/// PS3.3 2026a Table C.24-2 (Encapsulated Document Length) and Table C.12-1 (Specific
/// Character Set) in the shared builder and parser (D181, D182).
final class EncapsulatedDocumentLengthTests: XCTestCase {

    private let lengthTag = Tag(group: 0x0042, element: 0x0015)
    private let oddPDF = Data("%PDF-1.4\n%%EOF".utf8)   // 14 bytes … made odd below

    private func builder(_ data: Data) -> EncapsulatedDocumentBuilder {
        EncapsulatedDocumentBuilder(documentData: data, mimeType: "application/pdf", documentType: .pdf,
                                    studyInstanceUID: "1.2.3", seriesInstanceUID: "1.2.3.4")
    }

    /// D182 + D181: the length "not including any trailing padding" is written, and the
    /// parser returns the document without the padding byte DICOM adds to an odd length.
    func testOddLengthDocumentRoundTripsWithoutThePaddingByte() throws {
        let document = oddPDF + Data("\n".utf8)   // 15 bytes
        let dataSet = try builder(document).buildDataSet()
        XCTAssertEqual(dataSet.uint32(for: lengthTag), 15)

        let file = DICOMFile.create(dataSet: dataSet, sopClassUID: EncapsulatedDocument.encapsulatedPDFStorageUID,
                                    transferSyntaxUID: "1.2.840.10008.1.2.1")
        let read = try DICOMFile.read(from: file.write()).dataSet
        XCTAssertEqual(read[.encapsulatedDocument]?.valueData.count, 16, "value padded to even length")
        let parsed = try EncapsulatedDocumentParser.parse(from: read)
        XCTAssertEqual(parsed.documentData, document)
        XCTAssertTrue(parsed.metadataReport().contains("Size: 15 bytes"), parsed.metadataReport())
    }

    /// Without (0042,0015) (Type 3) the stored value is returned unchanged.
    func testDocumentWithoutLengthIsReturnedAsStored() {
        var dataSet = DataSet()
        dataSet.setString("x", for: .patientName, vr: .PN)
        let value = Data([1, 2, 3, 0])
        XCTAssertEqual(EncapsulatedDocumentParser.documentStream(value, in: dataSet), value)
        dataSet[lengthTag] = DataElement.uint32(tag: lengthTag, value: 3)
        XCTAssertEqual(EncapsulatedDocumentParser.documentStream(value, in: dataSet), Data([1, 2, 3]))
        dataSet[lengthTag] = DataElement.uint32(tag: lengthTag, value: 1)
        XCTAssertEqual(EncapsulatedDocumentParser.documentStream(value, in: dataSet), value,
                       "a length that is neither VL nor VL-1 is not trusted")
    }

    /// D182: Specific Character Set ISO_IR 192 when a value is not ASCII (Tables C.12-1, C.12-5).
    func testNonASCIITextGetsISOIR192() throws {
        let utf8 = try builder(oddPDF).setPatientName("Müller^Jörg").setDocumentTitle("Befund für Jörg").buildDataSet()
        XCTAssertEqual(utf8.string(for: .specificCharacterSet), "ISO_IR 192")
        XCTAssertNil(try builder(oddPDF).setPatientName("DOE^John").buildDataSet()[.specificCharacterSet])
        let plain = try builder(oddPDF).setPatientName("Müller^Jörg").build().toDataSet()
        XCTAssertEqual(plain.string(for: .specificCharacterSet), "ISO_IR 192")
    }
}
