//
// EncapsulationAttributesTests.swift
// dicom-pdf
//
// G3 contract (2026-10-01), values dumped by script from the 2026a DocBook:
//   - PS3.3 Table C.24-2: Encapsulated Document Length (0042,0015) is "the length of the
//     Encapsulated Document stream, not including any trailing padding"; Burned In
//     Annotation (0028,0301) Type 1; HL7 Instance Identifier (0040,E001) Type 1C,
//     "Required if encapsulated document is a CDA document", UID^Extension;
//   - PS3.3 Table C.8-24: Conversion Type (0008,0064) Defined Terms DV DI DF WSD SD SI DRW SYN;
//   - PS3.3 Table C.12-1 / C.12-5: Specific Character Set (0008,0005) Type 1C, ISO_IR 192 = UTF-8;
//   - PS3.3 A.45.1.4.1: MIME Type application/pdf; PS3.6 Table A-1: Encapsulated PDF
//     Storage 1.2.840.10008.5.1.4.1.1.104.1.
//

import XCTest
import DICOMKit
import DICOMCore
@testable import dicom_pdf

final class EncapsulationAttributesTests: XCTestCase {

    // MARK: - Vocabularies

    func test_conversionTypes_areTheEightC824DefinedTerms() throws {
        XCTAssertEqual(EncapsulatedDocumentBuilder.OptionRules.conversionTypes, ["DV", "DI", "DF", "WSD", "SD", "SI", "DRW", "SYN"])
        XCTAssertEqual(EncapsulatedDocumentBuilder.OptionRules.conversionTypes, EncapsulatedDocumentBuilder.conversionTypeDefinedTerms)
        XCTAssertEqual(EncapsulatedDocumentBuilder.OptionRules.defaultConversionType, EncapsulatedDocumentBuilder.defaultConversionType)
        XCTAssertEqual(try EncapsulatedDocumentBuilder.OptionRules.conversionType("sd"), "SD")
        XCTAssertThrowsError(try EncapsulatedDocumentBuilder.OptionRules.conversionType("SCAN"))
    }

    func test_burnedInAnnotation_isYesOrNo() throws {
        XCTAssertEqual(EncapsulatedDocumentBuilder.OptionRules.burnedInAnnotationValues, ["YES", "NO"])
        XCTAssertTrue(try EncapsulatedDocumentBuilder.OptionRules.burnedInAnnotation("YES"))
        XCTAssertFalse(try EncapsulatedDocumentBuilder.OptionRules.burnedInAnnotation("no"))
        XCTAssertThrowsError(try EncapsulatedDocumentBuilder.OptionRules.burnedInAnnotation("Y"))
    }

    func test_hl7InstanceIdentifier_isClinicalDocumentIdRootCaretExtension() {
        XCTAssertEqual(EncapsulatedDocumentBuilder.OptionRules.hl7InstanceIdentifier(fromCDA: Self.cda(extension: "X1")),
                       "2.16.840.1.113883.19^X1")
        XCTAssertEqual(EncapsulatedDocumentBuilder.OptionRules.hl7InstanceIdentifier(fromCDA: Self.cda(extension: nil)),
                       "2.16.840.1.113883.19")
        XCTAssertNil(EncapsulatedDocumentBuilder.OptionRules.hl7InstanceIdentifier(
            fromCDA: Data(#"<Other><id root="1.2.3"/></Other>"#.utf8)))
    }

    // MARK: - Padding

    func test_documentBytes_cutsToEncapsulatedDocumentLength_onlyWhenPresentAndShorter() {
        let padded = Data([1, 2, 3, 0])
        var dataSet = DataSet()
        XCTAssertEqual(EncapsulatedDocumentBuilder.OptionRules.documentBytes(padded, in: dataSet), padded, "no (0042,0015): as stored")
        dataSet[EncapsulatedDocumentBuilder.OptionRules.encapsulatedDocumentLength] = .uint32(
            tag: EncapsulatedDocumentBuilder.OptionRules.encapsulatedDocumentLength, value: 3)
        XCTAssertEqual(EncapsulatedDocumentBuilder.OptionRules.documentBytes(padded, in: dataSet), Data([1, 2, 3]))
        dataSet[EncapsulatedDocumentBuilder.OptionRules.encapsulatedDocumentLength] = .uint32(
            tag: EncapsulatedDocumentBuilder.OptionRules.encapsulatedDocumentLength, value: 9)
        XCTAssertEqual(EncapsulatedDocumentBuilder.OptionRules.documentBytes(padded, in: dataSet), padded, "longer than the value: ignored")
    }

    // MARK: - Round trip through the CLI

    func test_oddLengthPDF_roundTripsByteForByte_withTheC242Attributes() throws {
        let dir = try temporaryDirectory()
        let pdf = Self.pdf(oddLength: true)
        XCTAssertEqual(pdf.count % 2, 1)
        let input = dir.appendingPathComponent("report.pdf")
        let encapsulated = dir.appendingPathComponent("report.dcm")
        let extracted = dir.appendingPathComponent("back.pdf")
        try pdf.write(to: input)

        var encapsulate = try DICOMPdf.parse([
            input.path, "--output", encapsulated.path,
            "--patient-name", "Müller^Jörg", "--patient-id", "P1", "--title", "Befund",
            "--conversion-type", "SD", "--burned-in-annotation", "NO",
        ])
        try encapsulate.run()

        let file = try DICOMFile.read(from: try Data(contentsOf: encapsulated))
        let dataSet = file.dataSet
        XCTAssertEqual(dataSet.string(for: .sopClassUID), "1.2.840.10008.5.1.4.1.1.104.1")
        XCTAssertEqual(dataSet.string(for: .mimeTypeOfEncapsulatedDocument), "application/pdf")
        XCTAssertEqual(dataSet[EncapsulatedDocumentBuilder.OptionRules.encapsulatedDocumentLength]?.vr, .UL)
        XCTAssertEqual(dataSet[EncapsulatedDocumentBuilder.OptionRules.encapsulatedDocumentLength]?.uint32Value, UInt32(pdf.count))
        let value = try XCTUnwrap(dataSet[.encapsulatedDocument]?.valueData)
        XCTAssertEqual(value.count, pdf.count + 1, "OB value padded to even length")
        XCTAssertEqual(dataSet.string(for: .conversionType), "SD")
        XCTAssertEqual(dataSet.string(for: .burnedInAnnotation), "NO")
        XCTAssertEqual(dataSet.string(for: .specificCharacterSet), "ISO_IR 192")
        XCTAssertNil(dataSet[.hl7InstanceIdentifier], "Type 1C: CDA only")

        var extract = try DICOMPdf.parse([encapsulated.path, "--output", extracted.path, "--extract"])
        try extract.run()
        XCTAssertEqual(try Data(contentsOf: extracted), pdf, "padding byte stripped via (0042,0015)")
    }

    func test_asciiPDF_hasNoSpecificCharacterSet_andDefaults() throws {
        let dir = try temporaryDirectory()
        let input = dir.appendingPathComponent("a.pdf")
        let output = dir.appendingPathComponent("a.dcm")
        try Self.pdf(oddLength: false).write(to: input)
        var encapsulate = try DICOMPdf.parse([input.path, "-o", output.path, "--patient-name", "DOE^JANE", "--patient-id", "P"])
        try encapsulate.run()
        let dataSet = try DICOMFile.read(from: try Data(contentsOf: output)).dataSet
        XCTAssertNil(dataSet[.specificCharacterSet])
        XCTAssertEqual(dataSet.string(for: .conversionType), "WSD")
        XCTAssertEqual(dataSet.string(for: .burnedInAnnotation), "YES")
        XCTAssertEqual(dataSet.string(for: .modality), "DOC")
    }

    func test_cda_getsTheHL7InstanceIdentifier_andPDFRefusesTheOption() throws {
        let dir = try temporaryDirectory()
        let cda = dir.appendingPathComponent("cda.xml")
        let output = dir.appendingPathComponent("cda.dcm")
        try Self.cda(extension: "X1").write(to: cda)
        var derived = try DICOMPdf.parse([cda.path, "-o", output.path, "--patient-name", "A", "--patient-id", "P"])
        try derived.run()
        var dataSet = try DICOMFile.read(from: try Data(contentsOf: output)).dataSet
        XCTAssertEqual(dataSet.string(for: .hl7InstanceIdentifier), "2.16.840.1.113883.19^X1")
        XCTAssertEqual(dataSet.string(for: .mimeTypeOfEncapsulatedDocument), "text/XML", "A.45.2.4")

        var given = try DICOMPdf.parse([cda.path, "-o", output.path, "--patient-name", "A", "--patient-id", "P",
                                        "--hl7-instance-identifier", "1.2.3^E"])
        try given.run()
        dataSet = try DICOMFile.read(from: try Data(contentsOf: output)).dataSet
        XCTAssertEqual(dataSet.string(for: .hl7InstanceIdentifier), "1.2.3^E")

        let pdf = dir.appendingPathComponent("r.pdf")
        try Self.pdf(oddLength: true).write(to: pdf)
        var refused = try DICOMPdf.parse([pdf.path, "-o", output.path, "--patient-name", "A", "--patient-id", "P",
                                          "--hl7-instance-identifier", "1.2.3"])
        XCTAssertThrowsError(try refused.run())
    }

    // MARK: - Fixtures

    private func temporaryDirectory() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("dicom-pdfTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }
        return dir
    }

    /// A minimal one-page PDF; `oddLength` adds or omits a final newline to fix parity.
    static func pdf(oddLength: Bool) -> Data {
        let objects = ["<< /Type /Catalog /Pages 2 0 R >>",
                       "<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
                       "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 200 200] >>"]
        var text = "%PDF-1.4\n"
        var offsets: [Int] = []
        for (index, object) in objects.enumerated() {
            offsets.append(text.utf8.count)
            text += "\(index + 1) 0 obj\n\(object)\nendobj\n"
        }
        let xref = text.utf8.count
        text += "xref\n0 4\n0000000000 65535 f \n"
        for offset in offsets { text += String(format: "%010d 00000 n \n", offset) }
        text += "trailer\n<< /Size 4 /Root 1 0 R >>\nstartxref\n\(xref)\n%%EOF"
        var data = Data(text.utf8)
        if (data.count % 2 == 1) != oddLength { data.append(0x0A) }
        return data
    }

    static func cda(extension ext: String?) -> Data {
        let extAttr = ext.map { #" extension="\#($0)""# } ?? ""
        return Data(#"<?xml version="1.0"?><ClinicalDocument xmlns="urn:hl7-org:v3"><id root="2.16.840.1.113883.19"\#(extAttr)/></ClinicalDocument>"#.utf8)
    }
}
