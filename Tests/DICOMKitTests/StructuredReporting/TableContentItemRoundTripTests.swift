import XCTest
import DICOMCore
@testable import DICOMKit

/// TABLE content items (PS3.3 2026a C.18.10) round-trip through the SR serializer and parser (P8).
final class TableContentItemRoundTripTests: XCTestCase {

    private func concept(_ v: String, _ m: String, scheme: CodingSchemeDesignator = .DCM) -> CodedConcept {
        CodedConcept(codeValue: v, scheme: scheme, codeMeaning: m)
    }

    private func sampleTable() -> TableContentItem {
        TableContentItem(
            conceptName: concept("113740", "Table of dose values"),
            rows: 2, columns: 3,
            rowDefinitions: [
                .init(index: 1, concept: concept("113853", "Row one")),
                .init(index: 2, concept: concept("113854", "Row two")),
            ],
            columnDefinitions: [
                .init(concept: concept("113855", "Every column"), units: concept("mGy", "mGy", scheme: .UCUM)),
            ],
            cells: [
                .init(row: 1, value: .decimal([1.5, 2.5, 3.5]), units: concept("mGy", "mGy", scheme: .UCUM)),
                .init(row: 2, column: 1, value: .text(["low"])),
                .init(row: 2, column: 2, value: .integer([42])),
                .init(row: 2, column: 3, value: .absent, qualifier: concept("114006", "Measurement failure")),
            ],
            relationshipType: .contains)
    }

    private func document(with table: TableContentItem, type: SRDocumentType = .extensibleSR) -> SRDocument {
        let root = ContainerContentItem(
            conceptName: concept("126000", "Imaging Measurement Report"),
            continuityOfContent: .separate,
            contentItems: [AnyContentItem(table)],
            relationshipType: nil)
        return SRDocument(sopClassUID: type.sopClassUID, sopInstanceUID: "1.2.3.4.5.6.7.8.9",
                          patientID: "P1", studyInstanceUID: "1.2.3", rootContent: root)
    }

    func testTableRoundTrips() throws {
        let original = sampleTable()
        let dataSet = try SRDocumentSerializer().serialize(document: document(with: original))
        let parsed = try SRDocumentParser().parse(dataSet: dataSet)

        let item = try XCTUnwrap(parsed.rootContent.contentItems.first)
        XCTAssertEqual(item.valueType, .table)
        let table = try XCTUnwrap(item.asTable)
        XCTAssertEqual(table.rows, 2)
        XCTAssertEqual(table.columns, 3)
        XCTAssertEqual(table.rowDefinitions, original.rowDefinitions)
        XCTAssertEqual(table.columnDefinitions, original.columnDefinitions)
        XCTAssertEqual(table.cells, original.cells)
        XCTAssertEqual(table.conceptName?.codeValue, "113740")
    }

    func testSerializedElementsFollowTheMacro() throws {
        let dataSet = try SRDocumentSerializer().serialize(document: document(with: sampleTable()))
        let content = try XCTUnwrap(dataSet[.contentSequence]?.sequenceItems?.first)
        XCTAssertEqual(content.string(for: .valueType)?.trimmingCharacters(in: .whitespaces), "TABLE")
        let tabulated = try XCTUnwrap(content[.tabulatedValuesSequence]?.sequenceItems?.first)
        XCTAssertEqual(tabulated[.numberOfTableRows]?.uint32Value, 2)
        XCTAssertEqual(tabulated[.numberOfTableColumns]?.uint32Value, 3)
        let cells = try XCTUnwrap(tabulated[.cellValuesSequence]?.sequenceItems)
        XCTAssertEqual(cells.count, 4)
        // Whole-row numeric item: DS values, no column number, Selector Attribute VR = DS
        XCTAssertNil(cells[0][.tableColumnNumber])
        XCTAssertEqual(cells[0].string(for: .selectorAttributeVR)?.trimmingCharacters(in: .whitespaces), "DS")
        XCTAssertEqual(cells[0][.selectorDSValue]?.decimalStringValues?.map(\.value), [1.5, 2.5, 3.5])
        // Absent value carries only the qualifier
        XCTAssertNil(cells[3][.selectorAttributeVR])
        XCTAssertNotNil(cells[3][.numericValueQualifierCodeSequence])
    }

    func testCellLookupResolvesWholeRowItems() {
        let table = sampleTable()
        XCTAssertEqual(table.value(row: 1, column: 2), .decimal([2.5]))
        XCTAssertEqual(table.value(row: 2, column: 1), .text(["low"]))
        XCTAssertEqual(table.value(row: 2, column: 3), .absent)
        XCTAssertNil(table.value(row: 3, column: 1))
    }

    func testTableIsPermittedOnlyWhereA35Allows() {
        XCTAssertTrue(SRDocumentType.extensibleSR.allowedValueTypes.contains(.table))
        XCTAssertTrue(SRDocumentType.enhancedXRayRadiationDoseSR.allowedValueTypes.contains(.table))
        XCTAssertFalse(SRDocumentType.comprehensiveSR.allowedValueTypes.contains(.table))
        XCTAssertFalse(SRDocumentType.basicTextSR.allowedValueTypes.contains(.table))
    }
}
