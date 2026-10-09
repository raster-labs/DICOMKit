import Testing
import Foundation
@testable import DICOMKit
import DICOMCore

/// PS3.3 2026a Tables A.35.5-2 (Mammography CAD SR) and A.35.6-2 (Chest CAD SR) list no
/// DATETIME target value type, and PS3.16 TID 4019 (Algorithm Identification) has no date/time
/// row; its manufacturer row is (122405, DCM, "Algorithm Manufacturer") (D17). TID 4019 is
/// included under every Single Image Finding (TID 4006 row 5 / TID 4104 row 11) and every
/// Detection Performed (TID 4017 row 2), so the manufacturer TEXT appears once per inclusion.
@Suite("CAD SR builders: value types and TID 4019 codes")
struct CADSRBuilderValueTypeTests {

    private func walk(_ items: [AnyContentItem], _ visit: (AnyContentItem) -> Void) {
        for item in items {
            visit(item)
            // Children of every value type: CONTAINER contents and the Content Sequence of
            // CODE/IMAGE/SCOORD items (PS3.3 Table C.17-6)
            walk(item.contentItems, visit)
        }
    }

    private func imageReference() -> ImageReference {
        ImageReference(
            sopClassUID: "1.2.840.10008.5.1.4.1.1.1.2",
            sopInstanceUID: "1.2.3.4.5.6.7.8.9"
        )
    }

    @Test("Mammography CAD SR carries no DATETIME item and names the manufacturer with 122405")
    func mammographyCAD() throws {
        let document = try MammographyCADSRBuilder()
            .withPatientID("P1")
            .withPatientName("Doe^Jane")
            .withStudyInstanceUID("1.2.3.4.5")
            .withCADProcessingSummary(
                algorithmName: "MammoCAD",
                algorithmVersion: "2.1.0",
                manufacturer: "Example Medical Systems",
                processingDateTime: "20240115144500"
            )
            .addFinding(
                type: .mass,
                probability: 0.85,
                location: .point2D(x: 128.5, y: 256.3, imageReference: imageReference())
            )
            .build()

        var valueTypes: Set<ContentItemValueType> = []
        var manufacturerCodes: [String] = []
        walk(document.rootContent.contentItems) { item in
            valueTypes.insert(item.valueType)
            if item.conceptName?.codeValue == "122405" { manufacturerCodes.append(item.conceptName?.codeMeaning ?? "") }
            #expect(item.conceptName?.codeValue != "113878")
            #expect(item.conceptName?.codeValue != "111005")
        }
        #expect(!valueTypes.contains(.datetime))
        #expect(valueTypes.isSubset(of: Set(SRDocumentType.mammographyCADSR.allowedValueTypes)))
        #expect(valueTypes.contains(.scoord) && valueTypes.contains(.image))
        #expect(!manufacturerCodes.isEmpty && Set(manufacturerCodes) == ["Algorithm Manufacturer"])
    }

    @Test("Chest CAD SR carries no DATETIME item and names the manufacturer with 122405")
    func chestCAD() throws {
        let document = try ChestCADSRBuilder()
            .withPatientID("P1")
            .withPatientName("Doe^John")
            .withStudyInstanceUID("1.2.3.4.5")
            .withCADProcessingSummary(
                algorithmName: "ChestCAD",
                algorithmVersion: "3.2.0",
                manufacturer: "Example Medical Systems",
                processingDateTime: "20240101120000"
            )
            .addFinding(
                type: .nodule,
                probability: 0.92,
                location: .point2D(x: 256.5, y: 384.7, imageReference: imageReference())
            )
            .build()

        var valueTypes: Set<ContentItemValueType> = []
        var manufacturerCodes: [String] = []
        walk(document.rootContent.contentItems) { item in
            valueTypes.insert(item.valueType)
            if item.conceptName?.codeValue == "122405" { manufacturerCodes.append(item.conceptName?.codeMeaning ?? "") }
            #expect(item.conceptName?.codeValue != "113878")
            #expect(item.conceptName?.codeValue != "111005")
        }
        #expect(!valueTypes.contains(.datetime))
        #expect(valueTypes.isSubset(of: Set(SRDocumentType.chestCADSR.allowedValueTypes)))
        #expect(!manufacturerCodes.isEmpty && Set(manufacturerCodes) == ["Algorithm Manufacturer"])
    }
}
