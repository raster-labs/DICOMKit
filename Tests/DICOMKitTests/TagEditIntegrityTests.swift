import XCTest
import Foundation
import DICOMCore
@testable import DICOMKit

final class TagEditIntegrityTests: XCTestCase {
    private let editor = TagEditor()
    private let smallest = Tag(group: 0x0028, element: 0x0106)

    @discardableResult
    private func edit(_ dataset: inout DataSet, _ sets: [String], dryRun: Bool = false,
                      source: DataSet? = nil, selectors: [String] = [], deletes: [String] = []) throws -> [String] {
        try editor.applyCheckedChanges(to: &dataset, sets: sets, deletes: deletes, deletePrivate: false,
                                       sourceDataSet: source, copyTags: selectors, verbose: false, dryRun: dryRun)
    }

    func testNineMalformedEditsFailBothPathsWithoutPartialChanges() {
        let cases: [(String, String, String)] = [
            ("PatientAge=Y123", "(0010,1010)", "AS"),
            ("PatientBirthDate=20260231", "(0010,0030)", "DA"),
            ("PixelSpacing=1..2\\3", "(0028,0030)", "DS"),
            ("SeriesNumber=++1", "(0020,0011)", "IS"),
            ("AcquisitionDateTime=20269999112233", "(0008,002A)", "DT"),
            ("StudyTime=256199", "(0008,0030)", "TM"),
            ("StudyInstanceUID=1..02", "(0020,000D)", "UI"),
            ("Rows=1\\2", "(0028,0010)", "US"),
            ("RetrieveAETitle=Müller", "(0008,0054)", "AE")
        ]
        for (spec, tag, vr) in cases {
            for dryRun in [false, true] {
                var dataset = DataSet()
                dataset.setString("ORIGINAL^PATIENT", for: .patientName, vr: .PN)
                let before = dataset.write()
                XCTAssertThrowsError(try edit(&dataset, ["PatientID=NEW", spec], dryRun: dryRun, deletes: ["PatientName"])) { error in
                    let message = error.localizedDescription
                    XCTAssertTrue(message.contains(tag), message)
                    XCTAssertTrue(message.contains("VR \(vr)"), message)
                    XCTAssertTrue(message.contains("VM "), message)
                }
                XCTAssertEqual(dataset.write(), before, "\(spec), dryRun=\(dryRun)")
            }
        }
    }

    func testValidValuesEmptyValuesAndNumericBounds() throws {
        var dataset = DataSet()
        try edit(&dataset, ["Rows=512", "PatientAge=123Y", "PatientBirthDate=20240229", "PixelSpacing=1.25\\2.5",
                            "SeriesNumber=+1", "AcquisitionDateTime=2026+0530", "StudyTime=235960", "StudyInstanceUID=1.2.840.123", "RetrieveAETitle=ONE\\TWO"])
        XCTAssertEqual(dataset.uint16(for: .rows), 512)
        let before = dataset.write()
        XCTAssertThrowsError(try edit(&dataset, ["Rows=65536"]))
        XCTAssertEqual(dataset.write(), before)
        try edit(&dataset, ["PatientBirthDate=", "Rows="])
        XCTAssertEqual(dataset[.patientBirthDate]?.valueData.count, 0)
        XCTAssertEqual(dataset[.rows]?.valueData.count, 0)
    }

    func testMultiplicityFixedRangeAndStep() throws {
        var dataset = DataSet()
        XCTAssertThrowsError(try edit(&dataset, ["PixelSpacing=1"]))
        XCTAssertThrowsError(try edit(&dataset, ["PatientName=A\\B"]))
        try edit(&dataset, ["PixelSpacing=1\\2", "ImageType=ORIGINAL\\PRIMARY", "RetrieveAETitle=ONE\\TWO\\THREE"])
        XCTAssertEqual(dataset[.pixelSpacing]?.stringValues, ["1", "2"])
        // PS3.6 (0022,0032) Reference Coordinates is FL VM 2-2n.
        XCTAssertThrowsError(try edit(&dataset, ["ReferenceCoordinates=1\\2\\3"]))
        try edit(&dataset, ["ReferenceCoordinates=1\\2\\3\\4"])
        // (0070,0022) Graphic Data is FL VM 2-n and permits an odd count.
        try edit(&dataset, ["GraphicData=1\\2\\3"])
    }

    func testCopySelectorFormsAndRefusals() throws {
        let expected = ["00100010", "00080020", "00100020"]
        for selectors in ["0010,0010,0008,0020,PatientID", "(0010,0010),StudyDate;00100020", "PatientName,StudyDate,PatientID"] {
            XCTAssertEqual(try editor.parseTagSelectors(selectors), expected)
        }
        for invalid in ["0010", "0010,xyz", "NoSuchTag", "PatientName,", ";PatientName", "((0010,0010))", "(0010,0010", "0010;0010"] {
            XCTAssertThrowsError(try editor.parseTagSelectors(invalid), invalid)
        }
        var source = DataSet()
        source.setString("SOURCE^NAME", for: .patientName, vr: .PN)
        for selector in ["0010,0010", "PatientName"] {
            var dataset = DataSet()
            let lines = try edit(&dataset, [], source: source, selectors: editor.parseTagSelectors(selector))
            XCTAssertEqual(lines.count, 1)
            XCTAssertEqual(dataset[.patientName]?.vr, source[.patientName]?.vr)
            XCTAssertEqual(dataset[.patientName]?.valueData, source[.patientName]?.valueData)
        }
        var dataset = DataSet()
        let before = dataset.write()
        XCTAssertThrowsError(try edit(&dataset, [], source: source, selectors: ["NoSuchTag"]))
        XCTAssertThrowsError(try edit(&dataset, [], source: source, selectors: ["StudyDate"]))
        XCTAssertEqual(dataset.write(), before)
    }

    func testSignedValueUsesFinalContextInBothSetOrders() throws {
        for sets in [["SmallestImagePixelValue=-1", "PixelRepresentation=1"],
                     ["PixelRepresentation=1", "SmallestImagePixelValue=-1"]] {
            var dataset = DataSet()
            dataset.setUInt16(0, for: .pixelRepresentation)
            let before = dataset.write()
            let preview = try edit(&dataset, sets, dryRun: true)
            XCTAssertEqual(dataset.write(), before)
            XCTAssertEqual(try edit(&dataset, sets), preview)
            XCTAssertEqual(dataset[smallest]?.vr, .SS)
            XCTAssertEqual(dataset[smallest]?.int16Value, -1)
            XCTAssertEqual(dataset[smallest]?.valueData, Data([0xFF, 0xFF]))
        }
    }

    func testUnsignedAmbiguousAndExistingSignedControls() throws {
        var dataset = DataSet()
        XCTAssertThrowsError(try edit(&dataset, ["SmallestImagePixelValue=-1"]))
        XCTAssertThrowsError(try edit(&dataset, ["PixelRepresentation=0", "SmallestImagePixelValue=-1"]))
        XCTAssertThrowsError(try edit(&dataset, ["PixelRepresentation=2", "SmallestImagePixelValue=1"]))
        try edit(&dataset, ["PixelRepresentation=0", "SmallestImagePixelValue=65535"])
        XCTAssertEqual(dataset[smallest]?.vr, .US)
        XCTAssertEqual(dataset[smallest]?.uint16Value, 65535)
        dataset.remove(tag: .pixelRepresentation)
        dataset[smallest] = .int16(tag: smallest, value: -1)
        try edit(&dataset, ["SmallestImagePixelValue=-2"])
        XCTAssertEqual(dataset[smallest]?.vr, .SS)
        XCTAssertEqual(dataset[smallest]?.int16Value, -2)
    }

    func testSignedValuesRoundTripExplicitAndImplicitAndExplicitVRIsPreserved() throws {
        var dataset = DataSet()
        try edit(&dataset, ["PixelRepresentation=1", "SmallestImagePixelValue=-1"])
        for transferSyntax in ["1.2.840.10008.1.2", "1.2.840.10008.1.2.1"] {
            let file = DICOMFile.create(dataSet: dataset, sopInstanceUID: "1.2.3", transferSyntaxUID: transferSyntax)
            let read = try DICOMFile.read(from: file.write())
            XCTAssertEqual(read.dataSet[smallest]?.vr, .SS, transferSyntax)
            XCTAssertEqual(read.dataSet[smallest]?.int16Value, -1, transferSyntax)
        }
        dataset[smallest] = .uint16(tag: smallest, value: 65535)
        let explicit = DICOMFile.create(dataSet: dataset, sopInstanceUID: "1.2.3")
        XCTAssertEqual(try DICOMFile.read(from: explicit.write()).dataSet[smallest]?.vr, .US,
                       "An explicit wrong VR is retained for validation, never silently repaired")
    }

    func testImplicitItemContextInheritanceAndOverride() throws {
        var dataset = DataSet()
        dataset.setUInt16(1, for: .pixelRepresentation)
        let inherited = SequenceItem(elements: [.uint16(tag: smallest, value: 65535)])
        let overridden = SequenceItem(elements: [.uint16(tag: .pixelRepresentation, value: 0), .uint16(tag: smallest, value: 65535)])
        dataset.setSequence([inherited, overridden], for: .referencedImageSequence)
        let file = DICOMFile.create(dataSet: dataset, sopInstanceUID: "1.2.3", transferSyntaxUID: "1.2.840.10008.1.2")
        let read = try DICOMFile.read(from: file.write())
        let items = try XCTUnwrap(read.dataSet[.referencedImageSequence]?.sequenceItems)
        XCTAssertEqual(items[0][smallest]?.vr, .SS)
        XCTAssertEqual(items[0][smallest]?.int16Value, -1)
        XCTAssertEqual(items[1][smallest]?.vr, .US)
        XCTAssertEqual(items[1][smallest]?.uint16Value, 65535)
    }

    func testEmptyTypeTwoFieldAndRequiredSOPIdentityControls() throws {
        var dataset = DataSet()
        try edit(&dataset, ["PatientBirthDate=\\"])
        XCTAssertEqual(DICOMValueRules.valueCount(of: try XCTUnwrap(dataset[.patientBirthDate])), 0)
        dataset.setString("1.2.3", for: .sopClassUID, vr: .UI)
        dataset.setString("1.2.4", for: .sopInstanceUID, vr: .UI)
        let before = dataset.write()
        for spec in ["SOPClassUID=", "SOPClassUID=\\", "SOPInstanceUID=", "SOPInstanceUID=\\\\"] {
            XCTAssertThrowsError(try edit(&dataset, [spec]))
            XCTAssertThrowsError(try edit(&dataset, [spec], dryRun: true))
        }
        XCTAssertThrowsError(try edit(&dataset, [], deletes: ["SOPClassUID"]))
        XCTAssertThrowsError(try edit(&dataset, [], deletes: ["SOPInstanceUID"]))
        XCTAssertEqual(dataset.write(), before)
    }

    func testCompatibleLegacyCopyKeepsBytesAndNewTextPromotesWhenNecessary() throws {
        let name = DataElement(tag: .patientName, vr: .PN, length: 6,
                               valueData: Data([0x4D, 0xFC, 0x6C, 0x6C, 0x65, 0x72]), specificCharacterSet: "ISO_IR 100")
        let charset = DataElement.string(tag: .specificCharacterSet, vr: .CS, value: "ISO_IR 100")
        let source = DataSet(elements: [charset, name])
        var dataset = DataSet(elements: [charset])
        try edit(&dataset, [], source: source, selectors: editor.parseTagSelectors("0010,0010"))
        XCTAssertEqual(dataset[.patientName]?.valueData, name.valueData)
        XCTAssertEqual(dataset.string(for: .specificCharacterSet), "ISO_IR 100")
        try edit(&dataset, ["PatientName=山田^太郎"])
        XCTAssertEqual(dataset.string(for: .specificCharacterSet), "ISO_IR 192")
        XCTAssertEqual(dataset.string(for: .patientName), "山田^太郎")
        let before = dataset.write()
        XCTAssertThrowsError(try edit(&dataset, ["SpecificCharacterSet=ISO_IR 100"]))
        XCTAssertThrowsError(try edit(&dataset, [], deletes: ["SpecificCharacterSet"]))
        XCTAssertEqual(dataset.write(), before)
    }
}
