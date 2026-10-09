import XCTest
import DICOMCore
@testable import DICOMKit

/// The SR Document Series Module (PS3.3 2026a Table C.17-1), the SR Document General Module
/// (Table C.17-2), the Basic Code Sequence Macro (Table 8.8-1a) and TABLE integer cells
/// (Table C.18.10-1) as written by `SRDocumentSerializer` and read back by `SRDocumentParser`
/// (P-SRSER).
final class SRDocumentModuleRoundTripTests: XCTestCase {

    private func concept(_ v: String, _ m: String, scheme: CodingSchemeDesignator = .DCM) -> CodedConcept {
        CodedConcept(codeValue: v, scheme: scheme, codeMeaning: m)
    }

    private func document(
        type: SRDocumentType = .comprehensiveSR,
        modality: String? = nil,
        seriesNumber: String? = nil,
        instanceNumber: String? = nil,
        contentDate: String? = nil,
        contentTime: String? = nil,
        completionFlag: CompletionFlag? = nil,
        verificationFlag: VerificationFlag? = nil,
        title: CodedConcept? = nil,
        items: [AnyContentItem] = []
    ) -> SRDocument {
        let root = ContainerContentItem(
            conceptName: title ?? concept("126000", "Imaging Measurement Report"),
            continuityOfContent: .separate,
            contentItems: items)
        return SRDocument(
            sopClassUID: type.sopClassUID, sopInstanceUID: "1.2.3.4.5.6.7.8.9",
            patientID: "P1", studyInstanceUID: "1.2.3", seriesInstanceUID: "1.2.3.4",
            seriesNumber: seriesNumber, modality: modality,
            contentDate: contentDate, contentTime: contentTime, instanceNumber: instanceNumber,
            completionFlag: completionFlag, verificationFlag: verificationFlag,
            documentTitle: root.conceptName, rootContent: root)
    }

    private func roundTrip(_ document: SRDocument) throws -> (DataSet, SRDocument) {
        let dataSet = try SRDocumentSerializer().serialize(document: document)
        return (dataSet, try SRDocumentParser().parse(dataSet: dataSet))
    }

    // MARK: - SR Document Series Module (Table C.17-1)

    func testSeriesModuleDefaultsForADocumentThatCarriesNone() throws {
        let (dataSet, parsed) = try roundTrip(document())

        // Modality (0008,0060) Type 1, Enumerated Value SR
        XCTAssertEqual(dataSet.string(for: .modality), "SR")
        XCTAssertEqual(parsed.modality, "SR")
        // Series Instance UID (0020,000E) Type 1
        XCTAssertEqual(parsed.seriesInstanceUID, "1.2.3.4")
        // Series Number (0020,0011) Type 1
        XCTAssertEqual(dataSet[.seriesNumber]?.vr, .IS)
        XCTAssertEqual(parsed.seriesNumber, SRDocumentSerializer.defaultNumber)
        // Referenced Performed Procedure Step Sequence (0008,1111) Type 2: present, zero Items
        let pps = try XCTUnwrap(dataSet[.referencedPerformedProcedureStepSequence])
        XCTAssertEqual(pps.vr, .SQ)
        XCTAssertEqual(pps.sequenceItems?.count ?? 0, 0)
        XCTAssertEqual(pps.length, 0)
    }

    func testSeriesModuleRoundTripsProvidedValues() throws {
        let (dataSet, parsed) = try roundTrip(document(modality: "SR", seriesNumber: "7"))
        XCTAssertEqual(dataSet.string(for: .seriesNumber), "7")
        XCTAssertEqual(parsed.seriesNumber, "7")
        XCTAssertEqual(parsed.modality, "SR")
    }

    func testKeyObjectSelectionDocumentDefaultsToModalityKO() throws {
        // Table C.17.6-1 Key Object Document Series Module: Modality Enumerated Value KO
        let (dataSet, parsed) = try roundTrip(document(type: .keyObjectSelectionDocument))
        XCTAssertEqual(dataSet.string(for: .modality), "KO")
        XCTAssertEqual(parsed.modality, "KO")
        XCTAssertEqual(SRDocumentSerializer.defaultModality(forSOPClassUID: SRDocumentType.basicTextSR.sopClassUID), "SR")
        XCTAssertEqual(SRDocumentSerializer.defaultModality(forSOPClassUID: SRDocumentType.comprehensive3DSR.sopClassUID), "SR")
    }

    // MARK: - SR Document General Module (Table C.17-2)

    func testGeneralModuleType1AttributesAreAlwaysWritten() throws {
        let (dataSet, parsed) = try roundTrip(document())

        // Instance Number (0020,0013) Type 1
        XCTAssertEqual(parsed.instanceNumber, SRDocumentSerializer.defaultNumber)
        // Completion Flag (0040,A491) Type 1: PARTIAL when the document does not say
        XCTAssertEqual(dataSet.string(for: .completionFlag), "PARTIAL")
        XCTAssertEqual(parsed.completionFlag, .partial)
        // Verification Flag (0040,A493) Type 1: UNVERIFIED when the document does not say
        XCTAssertEqual(dataSet.string(for: .verificationFlag), "UNVERIFIED")
        XCTAssertEqual(parsed.verificationFlag, .unverified)
        // Content Date (0008,0023) / Content Time (0008,0033) Type 1: filled at serialization
        let contentDate = try XCTUnwrap(parsed.contentDate)
        let contentTime = try XCTUnwrap(parsed.contentTime)
        XCTAssertEqual(contentDate.count, 8)
        XCTAssertTrue(contentDate.allSatisfy(\.isNumber))
        XCTAssertEqual(contentTime.count, 6)
        XCTAssertTrue(contentTime.allSatisfy(\.isNumber))
        XCTAssertEqual(dataSet[.contentDate]?.vr, .DA)
        XCTAssertEqual(dataSet[.contentTime]?.vr, .TM)
        // Performed Procedure Code Sequence (0040,A372) Type 2: present, zero Items
        let ppcs = try XCTUnwrap(dataSet[.performedProcedureCodeSequence])
        XCTAssertEqual(ppcs.vr, .SQ)
        XCTAssertEqual(ppcs.sequenceItems?.count ?? 0, 0)
        // Preliminary Flag (0040,A496) Type 3: absent when not set
        XCTAssertNil(dataSet[.preliminaryFlag])
    }

    func testGeneralModuleRoundTripsProvidedValues() throws {
        let (dataSet, parsed) = try roundTrip(document(
            instanceNumber: "3", contentDate: "20260929", contentTime: "101500",
            completionFlag: .complete, verificationFlag: .verified)
            // VERIFIED requires the Verifying Observer Sequence (Type 1C, Table C.17-2; D37)
            .withVerifyingObservers([VerifyingObserver(
                name: "Smith^Jane", organization: "Radiology", verificationDateTime: "20260929101500")]))
        XCTAssertEqual(dataSet.string(for: .completionFlag), "COMPLETE")
        XCTAssertEqual(dataSet.string(for: .verificationFlag), "VERIFIED")
        XCTAssertEqual(parsed.instanceNumber, "3")
        XCTAssertEqual(parsed.contentDate, "20260929")
        XCTAssertEqual(parsed.contentTime, "101500")
        XCTAssertEqual(parsed.completionFlag, .complete)
        XCTAssertEqual(parsed.verificationFlag, .verified)
    }

    func testVerifiedRequiresComplete() {
        // Table C.17-2: "A Value of VERIFIED shall be used only when the Value of
        // Completion Flag (0040,A491) is COMPLETE."
        XCTAssertThrowsError(try SRDocumentSerializer().serialize(
            document: document(completionFlag: .partial, verificationFlag: .verified))) { error in
            guard case SRDocumentSerializer.SerializationError.inconsistentAttributes = error else {
                return XCTFail("expected inconsistentAttributes, got \(error)")
            }
        }
        XCTAssertThrowsError(try SRDocumentSerializer().serialize(
            document: document(completionFlag: nil, verificationFlag: .verified)))
    }

    // MARK: - Basic Code Sequence Macro (Table 8.8-1a)

    private func firstCodeItem(_ dataSet: DataSet) throws -> SequenceItem {
        let content = try XCTUnwrap(dataSet[.contentSequence]?.sequenceItems?.first)
        return try XCTUnwrap(content[.conceptCodeSequence]?.sequenceItems?.first)
    }

    private func codeDocument(_ code: CodedConcept) -> SRDocument {
        document(items: [AnyContentItem(CodeContentItem(
            conceptName: concept("121071", "Finding"), conceptCode: code, relationshipType: .contains))])
    }

    func testLongCodeValueOnlyIsWrittenWithoutCodeValue() throws {
        let long = CodedConcept(
            codeValue: "", codingSchemeDesignator: "99TEST", codeMeaning: "A long code",
            longCodeValue: "THIS-CODE-VALUE-IS-LONGER-THAN-SIXTEEN")
        let (dataSet, parsed) = try roundTrip(codeDocument(long))

        let item = try firstCodeItem(dataSet)
        XCTAssertNil(item[.codeValue], "Code Value shall be absent when Long Code Value is present")
        XCTAssertNil(item[.urnCodeValue])
        let longElement = try XCTUnwrap(item[.longCodeValue])
        XCTAssertEqual(longElement.vr, .UC)
        XCTAssertEqual(longElement.stringValue, "THIS-CODE-VALUE-IS-LONGER-THAN-SIXTEEN")
        XCTAssertEqual(item.string(for: .codingSchemeDesignator), "99TEST")
        XCTAssertEqual(item.string(for: .codeMeaning), "A long code")

        XCTAssertEqual(parsed.rootContent.contentItems.first?.asCode?.conceptCode, long)
    }

    func testCodeValueLongerThanSixteenCharactersBecomesLongCodeValue() throws {
        let long = CodedConcept(codeValue: "ABCDEFGHIJKLMNOPQ", codingSchemeDesignator: "99TEST", codeMeaning: "17 chars")
        let (dataSet, parsed) = try roundTrip(codeDocument(long))
        let item = try firstCodeItem(dataSet)
        XCTAssertNil(item[.codeValue])
        XCTAssertEqual(item.string(for: .longCodeValue), "ABCDEFGHIJKLMNOPQ")
        let read = try XCTUnwrap(parsed.rootContent.contentItems.first?.asCode?.conceptCode)
        XCTAssertEqual(read.longCodeValue, "ABCDEFGHIJKLMNOPQ")
        XCTAssertEqual(read.effectiveCodeValue, "ABCDEFGHIJKLMNOPQ")
    }

    func testURNCodeValueOnlyIsWrittenWithoutCodeValueOrDesignator() throws {
        let urn = CodedConcept(
            codeValue: "", codingSchemeDesignator: "", codeMeaning: "An IRI code",
            urnCodeValue: "http://example.org/codes/42")
        let (dataSet, parsed) = try roundTrip(codeDocument(urn))

        let item = try firstCodeItem(dataSet)
        XCTAssertNil(item[.codeValue])
        XCTAssertNil(item[.longCodeValue])
        let urnElement = try XCTUnwrap(item[.urnCodeValue])
        XCTAssertEqual(urnElement.vr, .UR)
        XCTAssertEqual(urnElement.stringValue, "http://example.org/codes/42")
        // Coding Scheme Designator is Type 1C only with Code Value / Long Code Value
        XCTAssertNil(item[.codingSchemeDesignator])
        XCTAssertNil(item[.codingSchemeVersion])
        XCTAssertEqual(item.string(for: .codeMeaning), "An IRI code")

        XCTAssertEqual(parsed.rootContent.contentItems.first?.asCode?.conceptCode, urn)
    }

    func testShortCodeValueIsWrittenAsCodeValueWithVersion() throws {
        let code = CodedConcept(codeValue: "4147007", codingSchemeDesignator: "SCT", codeMeaning: "Mass", codingSchemeVersion: "2026")
        let (dataSet, parsed) = try roundTrip(codeDocument(code))
        let item = try firstCodeItem(dataSet)
        XCTAssertEqual(item[.codeValue]?.vr, .SH)
        XCTAssertEqual(item.string(for: .codeValue), "4147007")
        XCTAssertNil(item[.longCodeValue])
        XCTAssertNil(item[.urnCodeValue])
        XCTAssertEqual(item.string(for: .codingSchemeVersion), "2026")
        XCTAssertEqual(parsed.rootContent.contentItems.first?.asCode?.conceptCode, code)
    }

    // MARK: - TABLE integer cells (Table C.18.10-1)

    private func tableDocument(_ values: [Int64]) -> SRDocument {
        let table = TableContentItem(
            conceptName: concept("113740", "Table of values"),
            rows: 1, columns: values.count,
            cells: [.init(row: 1, value: .integer(values))],
            relationshipType: .contains)
        return document(type: .extensibleSR, items: [AnyContentItem(table)])
    }

    private func firstCell(_ dataSet: DataSet) throws -> SequenceItem {
        let content = try XCTUnwrap(dataSet[.contentSequence]?.sequenceItems?.first)
        let tabulated = try XCTUnwrap(content[.tabulatedValuesSequence]?.sequenceItems?.first)
        return try XCTUnwrap(tabulated[.cellValuesSequence]?.sequenceItems?.first)
    }

    func testIntegerCellsWithinISRangeAreSelectorISValue() throws {
        let values: [Int64] = [-2_147_483_648, 0, 2_147_483_647]
        let (dataSet, parsed) = try roundTrip(tableDocument(values))
        let cell = try firstCell(dataSet)
        XCTAssertEqual(cell.string(for: .selectorAttributeVR), "IS")
        XCTAssertEqual(cell[.selectorISValue]?.vr, .IS)
        XCTAssertEqual(cell[.selectorISValue]?.integerStringValues?.map(\.value), [-2_147_483_648, 0, 2_147_483_647])
        XCTAssertNil(cell[.selectorSVValue])
        XCTAssertEqual(parsed.rootContent.contentItems.first?.asTable?.cells.first?.value, .integer(values))
    }

    func testIntegerCellsOutsideISRangeAreSelectorSVValue() throws {
        let values: [Int64] = [2_147_483_648, Int64.min, Int64.max]
        let (dataSet, parsed) = try roundTrip(tableDocument(values))
        let cell = try firstCell(dataSet)
        XCTAssertEqual(cell.string(for: .selectorAttributeVR), "SV")
        XCTAssertNil(cell[.selectorISValue])
        let sv = try XCTUnwrap(cell[.selectorSVValue])
        XCTAssertEqual(sv.vr, .SV)
        XCTAssertEqual(sv.length, 24)
        XCTAssertEqual(sv.int64Values, values)
        XCTAssertEqual(parsed.rootContent.contentItems.first?.asTable?.cells.first?.value, .integer(values))
    }

    func testIntegerSelectorVRChoice() {
        XCTAssertEqual(SRDocumentSerializer.integerSelectorVR([]), .IS)
        XCTAssertEqual(SRDocumentSerializer.integerSelectorVR([42]), .IS)
        XCTAssertEqual(SRDocumentSerializer.integerSelectorVR([Int64(Int32.max) + 1]), .SV)
        XCTAssertEqual(SRDocumentSerializer.integerSelectorVR([Int64(Int32.min) - 1]), .SV)
    }
}
