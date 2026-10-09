import XCTest
import ArgumentParser
import DICOMKit
import DICOMCore
@testable import dicom_gateway

/// P-GATEWAY-SC (closes D104): hl7-to-dicom / fhir-to-dicom write no instance that claims an
/// image Storage SOP Class without an image. The Secondary Capture Image IOD makes the Image
/// Pixel (C.7.6.3) and SC Image (C.8.6.2) Modules Mandatory (PS3.3 2026a Table A.8-1).
final class TemplateRequirementTests: XCTestCase {

    func testMissingTemplateIsRefusedWithExit1() {
        for (command, args) in [("hl7-to-dicom", ["msg.hl7", "--output", "o.dcm"]),
                                ("fhir-to-dicom", ["r.json", "--output", "o.dcm"])] {
            do {
                if command == "hl7-to-dicom" { _ = try HL7ToDICOM.parse(args) } else { _ = try FHIRToDICOM.parse(args) }
                XCTFail("\(command) without --template accepted")
            } catch {
                XCTAssertEqual(DICOMGateway.exitCode(for: error), .failure, command)   // exit 1, not 64
                let message = DICOMGateway.message(for: error)
                XCTAssertTrue(message.contains("--template"), message)
                XCTAssertTrue(message.contains("PS3.3 2026a Table A.8-1"), message)
            }
        }
        XCTAssertNoThrow(try HL7ToDICOM.parse(["msg.hl7", "--output", "o.dcm", "--template", "t.dcm"]))
        XCTAssertNoThrow(try FHIRToDICOM.parse(["r.json", "--output", "o.dcm", "--template", "t.dcm"]))
    }

    func testImageStorageClassesAreRecognised() {
        XCTAssertTrue(GatewayOutputRules.isImageStorage("1.2.840.10008.5.1.4.1.1.7"))      // Secondary Capture Image Storage
        XCTAssertTrue(GatewayOutputRules.isImageStorage("1.2.840.10008.5.1.4.1.1.2"))      // CT Image Storage
        XCTAssertTrue(GatewayOutputRules.isImageStorage("1.2.840.10008.5.1.4.1.1.6"))      // Ultrasound Image Storage (Retired)
        XCTAssertFalse(GatewayOutputRules.isImageStorage("1.2.840.10008.5.1.4.1.1.88.11")) // Basic Text SR Storage
        XCTAssertFalse(GatewayOutputRules.isImageStorage("1.2.840.10008.5.1.4.1.1.104.1")) // Encapsulated PDF Storage
        XCTAssertFalse(GatewayOutputRules.isImageStorage("1.2.840.10008.3.1.2.3.3"))       // MPPS, not storage
    }

    private func file(sopClass: String, pixels: Bool) -> DICOMFile {
        var dataSet = DataSet()
        dataSet.setString(sopClass, for: .sopClassUID, vr: .UI)
        dataSet.setString("1.2.3.4", for: .sopInstanceUID, vr: .UI)
        if pixels {
            dataSet[Tag(group: 0x7FE0, element: 0x0010)] =
                DataElement(tag: Tag(group: 0x7FE0, element: 0x0010), vr: .OW, length: 4, valueData: Data([0, 0, 0, 0]))
        }
        return DICOMFile.create(dataSet: dataSet, sopClassUID: sopClass, sopInstanceUID: "1.2.3.4")
    }

    func testTemplateClaimingAnImageWithoutPixelDataIsRefused() {
        XCTAssertThrowsError(try GatewayOutputRules.checkTemplate(
            file(sopClass: "1.2.840.10008.5.1.4.1.1.7", pixels: false), path: "t.dcm")) { error in
            XCTAssertTrue("\(error)".contains("Secondary Capture Image Storage"))
            XCTAssertTrue("\(error)".contains("Table A.8-1"))
        }
        XCTAssertNoThrow(try GatewayOutputRules.checkTemplate(
            file(sopClass: "1.2.840.10008.5.1.4.1.1.7", pixels: true), path: "t.dcm"))
        XCTAssertNoThrow(try GatewayOutputRules.checkTemplate(
            file(sopClass: "1.2.840.10008.5.1.4.1.1.88.11", pixels: false), path: "t.dcm"))
    }

    func testHelpSaysTemplateIsRequired() {
        for help in [HL7ToDICOM.helpMessage(), FHIRToDICOM.helpMessage()] {
            let flat = help.split(whereSeparator: \.isWhitespace).joined(separator: " ")
            XCTAssertTrue(flat.contains("--template is required"), flat)
            XCTAssertTrue(flat.contains("PS3.3 Table A.8-1"), flat)
        }
    }

    /// D214: `listen --forward` builds no template-less data set and says why, with the
    /// P-GATEWAY-SC reason (PS3.3 2026a Table A.8-1); forwarding itself is not implemented (D103).
    func testListenerForwardIsSkippedWithTheTemplateReason() throws {
        let note = try GatewayOutputRules.listenerForwardSkipMessage(
            messageType: "ORM", destination: "pacs://archive.example:11112")
        XCTAssertTrue(note.hasPrefix("Not forwarded to archive.example:11112: ORM message not converted"), note)
        XCTAssertTrue(note.contains(GatewayOutputRules.noImageReason), note)
        XCTAssertTrue(note.contains("PS3.3 2026a Table A.8-1"), note)
        XCTAssertTrue(note.contains("not implemented (D103)"), note)
        XCTAssertTrue(GatewayOutputRules.missingTemplateMessage(command: "hl7-to-dicom")
            .contains(GatewayOutputRules.noImageReason))
        XCTAssertThrowsError(try GatewayOutputRules.listenerForwardSkipMessage(
            messageType: "ORM", destination: "archive.example"))
    }
}
