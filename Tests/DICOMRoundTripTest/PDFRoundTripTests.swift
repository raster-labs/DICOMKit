// PDFRoundTripTests.swift
// Round-trip oracle tests for the `dicom-pdf` tool.
//
// Tests exercise the DICOMKit library directly (EncapsulatedDocumentBuilder /
// EncapsulatedDocumentParser / DICOMFile) — the same API the CLI calls — and
// assert only oracles that are true by definition (byte-identical round-trip,
// SOP-class match, MIME/extension mappings, transfer-syntax preservation).

import XCTest
import Foundation
@testable import DICOMKit
@testable import DICOMCore

final class PDFRoundTripTests: XCTestCase {

    // MARK: - Private helpers (kept inside the class so they don't collide)

    /// Minimal, valid-enough PDF payload (matches the plan's `%PDF-1.4\n%%EOF`).
    private func minimalPDF() -> Data {
        Data("%PDF-1.4\n%%EOF".utf8)
    }

    /// Encapsulate `data` of `type` into a DICOM file, then read it back through
    /// `DICOMFile.write()` / `DICOMFile.read(from:)`. Returns the parsed document.
    private func roundTrip(
        data: Data,
        type: EncapsulatedDocumentType,
        patientName: String = "Doe^John",
        patientID: String = "12345",
        title: String? = nil,
        seriesDescription: String? = nil,
        seriesNumber: Int? = nil,
        instanceNumber: Int? = nil,
        hl7InstanceIdentifier: String? = nil
    ) throws -> (parsed: EncapsulatedDocument, file: DICOMFile, bytes: Data) {
        var builder = EncapsulatedDocumentBuilder(
            documentData: data,
            mimeType: type.expectedMIMEType,
            documentType: type,
            studyInstanceUID: rtUID(),
            seriesInstanceUID: rtUID()
        )
        .applyStandardOptions(
            patientName: patientName,
            patientID: patientID,
            modality: type.defaultModality,
            title: title,
            seriesDescription: seriesDescription,
            seriesNumber: seriesNumber,
            instanceNumber: instanceNumber
        )
        // HL7 Instance Identifier (0040,E001) is Type 1C, "Required if
        // encapsulated document is a CDA document" (PS3.3 Table C.24-2).
        if let hl7InstanceIdentifier {
            builder = builder.setHL7InstanceIdentifier(hl7InstanceIdentifier)
        }
        let dataSet = try builder.buildDataSet()
        let dicomFile = DICOMFile.create(
            dataSet: dataSet,
            sopClassUID: type.sopClassUID,
            transferSyntaxUID: "1.2.840.10008.1.2.1"
        )
        let written = try dicomFile.write()
        let readFile = try DICOMFile.read(from: written)
        let parsed = try EncapsulatedDocumentParser.parse(from: readFile.dataSet)
        return (parsed, readFile, written)
    }

    // MARK: - Tests

    // Oracle: extracted document bytes are byte-identical to the original PDF.
    func testWrapExtractPDFBytesIdentical() throws {
        let pdf = minimalPDF()
        let rt = try roundTrip(data: pdf, type: .pdf)
        XCTAssertEqual(rt.parsed.documentData, pdf)
    }

    // Oracle: encapsulated PDF carries the Encapsulated PDF Storage SOP Class UID,
    // and it matches in both the file-meta and the dataset after round-trip.
    func testPDFSOPClassUID() throws {
        let rt = try roundTrip(data: minimalPDF(), type: .pdf)
        XCTAssertEqual(rt.parsed.sopClassUID, "1.2.840.10008.5.1.4.1.1.104.1")
        XCTAssertEqual(rt.parsed.documentType, .pdf)
        // File-meta and dataset both hold the same SOP Class per PS3.10.
        XCTAssertEqual(rt.file.sopClassUID, "1.2.840.10008.5.1.4.1.1.104.1")
        XCTAssertEqual(rt.file.dataSet.string(for: .sopClassUID), "1.2.840.10008.5.1.4.1.1.104.1")
    }

    // Oracle: encapsulated element begins with the "%PDF" signature after round-trip.
    func testEncapsulatedElementStartsWithPDFMagic() throws {
        let rt = try roundTrip(data: minimalPDF(), type: .pdf)
        let element = try XCTUnwrap(rt.file.dataSet[.encapsulatedDocument])
        let head = element.valueData.prefix(4)
        XCTAssertEqual(Array(head), Array("%PDF".utf8))
    }

    // Oracle: written file begins with a 128-byte preamble followed by the "DICM" magic (PS3.10).
    func testWrittenFileHasDICMPrefix() throws {
        let rt = try roundTrip(data: minimalPDF(), type: .pdf)
        XCTAssertGreaterThan(rt.bytes.count, 132)
        let magic = rt.bytes.subdata(in: 128..<132)
        XCTAssertEqual(Array(magic), Array("DICM".utf8))
    }

    // Oracle: transfer syntax (Explicit VR LE) is preserved through create/write/read.
    func testTransferSyntaxPreserved() throws {
        let rt = try roundTrip(data: minimalPDF(), type: .pdf)
        XCTAssertEqual(rt.file.transferSyntaxUID, "1.2.840.10008.1.2.1")
    }

    // Oracle: patient/series encapsulation options persist verbatim into the parsed document.
    func testStandardOptionsPersist() throws {
        let rt = try roundTrip(
            data: minimalPDF(),
            type: .pdf,
            patientName: "Smith^Jane",
            patientID: "RT-999",
            title: "Radiology Report",
            seriesDescription: "Reports",
            seriesNumber: 7,
            instanceNumber: 3
        )
        XCTAssertEqual(rt.parsed.patientName, "Smith^Jane")
        XCTAssertEqual(rt.parsed.patientID, "RT-999")
        XCTAssertEqual(rt.parsed.documentTitle, "Radiology Report")
        XCTAssertEqual(rt.parsed.seriesDescription, "Reports")
        XCTAssertEqual(rt.parsed.seriesNumber, 7)
        XCTAssertEqual(rt.parsed.instanceNumber, 3)
        XCTAssertEqual(rt.parsed.modality, "DOC")
        XCTAssertEqual(rt.parsed.mimeType, "application/pdf")
    }

    // Oracle: attributes the caller did not set are written as their Type requires
    // (PS3.3 2026a Tables C.24-1, C.24-2): Series Number and Instance Number are
    // Type 1 and default to 1; Document Title is Type 2, present and empty
    // (PS3.5 7.4.3); Series Description is Type 3 and stays absent. Required fields
    // carry the correct VR.
    func testUnsetFieldsFollowTheirType() throws {
        let rt = try roundTrip(data: minimalPDF(), type: .pdf)
        XCTAssertNil(rt.parsed.seriesDescription)
        XCTAssertEqual(rt.parsed.seriesNumber, 1)
        XCTAssertEqual(rt.parsed.instanceNumber, 1)
        XCTAssertEqual(rt.file.dataSet[.documentTitle]?.length, 0, "Type 2: present, empty")
        XCTAssertEqual(rt.parsed.documentTitle ?? "", "")
        XCTAssertNil(rt.file.dataSet[.seriesDescription])
        // Present required fields serialize with their correct VR.
        XCTAssertEqual(rt.file.dataSet[.patientName]?.vr, .PN)
        XCTAssertEqual(rt.file.dataSet[.patientID]?.vr, .LO)
        XCTAssertEqual(rt.file.dataSet[.modality]?.vr, .CS)
    }

    // Oracle: a CDA (XML) document round-trips byte-exact with the CDA SOP class + text/XML MIME.
    func testWrapExtractCDABytesIdentical() throws {
        let xml = Data("<ClinicalDocument>hello</ClinicalDocument>".utf8)
        let rt = try roundTrip(
            data: xml,
            type: .cda,
            title: "Discharge Summary",
            hl7InstanceIdentifier: "2.16.840.1.113883.19.999.1"
        )
        XCTAssertEqual(rt.parsed.documentData, xml)
        XCTAssertEqual(rt.parsed.documentType, .cda)
        XCTAssertEqual(rt.parsed.sopClassUID, "1.2.840.10008.5.1.4.1.1.104.2")
        // PS3.3 A.45.2.4: MIME Type of Encapsulated Document is Enumerated "text/XML"
        // (the attribute value; `expectedMIMEType` is the media type for extraction).
        XCTAssertEqual(rt.parsed.mimeType, "text/XML")
        XCTAssertEqual(rt.file.sopClassUID, "1.2.840.10008.5.1.4.1.1.104.2")
    }

    // Oracle: MIME-type mapping is fixed per document type (extract uses expectedMIMEType).
    func testMIMETypeMapping() {
        XCTAssertEqual(EncapsulatedDocumentType.pdf.expectedMIMEType, "application/pdf")
        XCTAssertEqual(EncapsulatedDocumentType.cda.expectedMIMEType, "text/xml")
        // PS3.3 A.85.1.4.2: MIME Type of Encapsulated Document is Enumerated "model/stl".
        XCTAssertEqual(EncapsulatedDocumentType.stl.expectedMIMEType, "model/stl")
        XCTAssertEqual(EncapsulatedDocumentType.obj.expectedMIMEType, "model/obj")
        XCTAssertEqual(EncapsulatedDocumentType.mtl.expectedMIMEType, "model/mtl")
    }

    // Oracle: file-extension mapping round-trips and is case-insensitive / dot-tolerant
    // (this is the extension the `extract` subcommand names its output file with).
    func testFileExtensionMappingRoundTrips() {
        for type in [EncapsulatedDocumentType.pdf, .cda, .stl, .obj, .mtl] {
            let ext = type.fileExtension
            XCTAssertEqual(EncapsulatedDocumentType(fileExtension: ext), type)
            XCTAssertEqual(EncapsulatedDocumentType(fileExtension: "." + ext.uppercased()), type)
        }
        // Unknown extensions resolve to .unknown, whose extension is "bin".
        XCTAssertEqual(EncapsulatedDocumentType(fileExtension: "zzz"), .unknown)
        XCTAssertEqual(EncapsulatedDocumentType.unknown.fileExtension, "bin")
    }

    // Oracle: SOP-Class-UID ⇄ document-type mapping is a bijection over known types.
    func testSOPClassUIDTypeRoundTrips() {
        for type in [EncapsulatedDocumentType.pdf, .cda, .stl, .obj, .mtl] {
            XCTAssertEqual(EncapsulatedDocumentType(sopClassUID: type.sopClassUID), type)
        }
    }

    // Oracle: default modality is M3D for 3D models, DOC otherwise (the encapsulate default).
    func testDefaultModality() {
        XCTAssertEqual(EncapsulatedDocumentType.pdf.defaultModality, "DOC")
        XCTAssertEqual(EncapsulatedDocumentType.cda.defaultModality, "DOC")
        XCTAssertEqual(EncapsulatedDocumentType.stl.defaultModality, "M3D")
        XCTAssertEqual(EncapsulatedDocumentType.obj.defaultModality, "M3D")
        XCTAssertEqual(EncapsulatedDocumentType.mtl.defaultModality, "M3D")
    }

    // Oracle: an STL (3D model) payload round-trips byte-exact with the STL SOP class,
    // model/stl MIME (A.85.1.4.2), and the M3D default modality.
    func testWrapExtractSTLBytesIdentical() throws {
        let stl = Data((0..<512).map { UInt8($0 % 256) })
        let rt = try roundTrip(data: stl, type: .stl)
        XCTAssertEqual(rt.parsed.documentData, stl)
        XCTAssertEqual(rt.parsed.documentType, .stl)
        XCTAssertEqual(rt.parsed.sopClassUID, "1.2.840.10008.5.1.4.1.1.104.3")
        XCTAssertEqual(rt.parsed.mimeType, "model/stl")
        XCTAssertEqual(rt.parsed.modality, "M3D")
    }

    // Oracle: a large binary payload survives the full round-trip byte-for-byte
    // (exercises the encapsulated OB element across a non-trivial length).
    func testLargePayloadByteExact() throws {
        var payload = minimalPDF()
        payload.append(Data((0..<50_000).map { UInt8(($0 * 31 + 7) % 256) }))
        let rt = try roundTrip(data: payload, type: .pdf)
        XCTAssertEqual(rt.parsed.documentData.count, payload.count)
        XCTAssertEqual(rt.parsed.documentData, payload)
    }

    // Oracle: content date/time set on the builder persist and re-parse to the same DICOM value.
    func testContentDateTimePersist() throws {
        let builder = EncapsulatedDocumentBuilder(
            documentData: minimalPDF(),
            mimeType: EncapsulatedDocumentType.pdf.expectedMIMEType,
            documentType: .pdf,
            studyInstanceUID: rtUID(),
            seriesInstanceUID: rtUID()
        )
        .applyStandardOptions(patientName: "Doe^John", patientID: "12345", modality: "DOC")
        .setContentDate(DICOMDate(year: 2026, month: 7, day: 1))
        .setContentTime(DICOMTime(hour: 13, minute: 30, second: 15))
        let ds = try builder.buildDataSet()
        let file = DICOMFile.create(
            dataSet: ds,
            sopClassUID: EncapsulatedDocumentType.pdf.sopClassUID,
            transferSyntaxUID: "1.2.840.10008.1.2.1"
        )
        let readFile = try DICOMFile.read(from: try file.write())
        let parsed = try EncapsulatedDocumentParser.parse(from: readFile.dataSet)
        XCTAssertEqual(parsed.contentDate?.dicomString, DICOMDate(year: 2026, month: 7, day: 1).dicomString)
        XCTAssertEqual(parsed.contentTime?.dicomString, DICOMTime(hour: 13, minute: 30, second: 15).dicomString)
    }

    // MARK: - modality override / supplied UIDs

    /// Build + round-trip an encapsulated PDF with explicit modality and study/series UIDs.
    private func buildEncapsulated(
        modality: String, studyUID: String, seriesUID: String
    ) throws -> DICOMFile {
        let builder = EncapsulatedDocumentBuilder(
            documentData: minimalPDF(),
            mimeType: EncapsulatedDocumentType.pdf.expectedMIMEType,
            documentType: .pdf,
            studyInstanceUID: studyUID,
            seriesInstanceUID: seriesUID
        )
        .applyStandardOptions(patientName: "Doe^John", patientID: "12345", modality: modality)
        let ds = try builder.buildDataSet()
        let file = DICOMFile.create(
            dataSet: ds,
            sopClassUID: EncapsulatedDocumentType.pdf.sopClassUID,
            transferSyntaxUID: "1.2.840.10008.1.2.1")
        return try DICOMFile.read(from: try file.write())
    }

    // Oracle: an explicit --modality overrides the document type's default (DOC for PDF)
    // and persists verbatim into Modality (0008,0060).
    func testExplicitModalityOverride() throws {
        let reread = try buildEncapsulated(modality: "SR", studyUID: rtUID(), seriesUID: rtUID())
        XCTAssertEqual(reread.dataSet.string(for: .modality), "SR")
        XCTAssertNotEqual(reread.dataSet.string(for: .modality),
                          EncapsulatedDocumentType.pdf.defaultModality,
                          "custom modality must override the default DOC")
    }

    // Oracle: supplied --study-uid / --series-uid persist verbatim into
    // (0020,000D)/(0020,000E) rather than being auto-generated.
    func testSuppliedStudySeriesUIDsPersist() throws {
        let study = "1.2.3.4.5.104.100", series = "1.2.3.4.5.104.200"
        let reread = try buildEncapsulated(modality: "DOC", studyUID: study, seriesUID: series)
        XCTAssertEqual(reread.dataSet.string(for: .studyInstanceUID), study)
        XCTAssertEqual(reread.dataSet.string(for: .seriesInstanceUID), series)
    }
}

