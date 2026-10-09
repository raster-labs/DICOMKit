//
// DIMSENStatusText2026aTests.swift
// DICOMNetworkTests
//
// Deferred rows D73, D79, D82, D83, D84, D86, D87, D91, D93 (2026-10-01): DIMSE-N,
// Modality Worklist, MPPS and Print Management status names verbatim from the DICOM
// 2026a DocBook, and the MPPS N-CREATE data set rules of PS3.4 F.7.2.1.
//

import XCTest
import Foundation
import DICOMCore
@testable import DICOMNetwork

final class DIMSENStatusText2026aTests: XCTestCase {

    /// PS3.4 2026a Tables K.4-1, F.7.2-2, F.8.2-2 and the 7 Annex H status tables,
    /// dumped by Scripts/nema_docbook.py: (table, Status Code, Service Status, Further Meaning).
    static let ps34Rows: [(table: String, service: DIMSEStatusService, code: String, status: String, meaning: String)] = [
        ("K.4-1", .mwlFind, "A700", "Failure", "Refused: Out of resources"),
        ("K.4-1", .mwlFind, "A900", "Failure", "Error: Data Set does not match SOP Class"),
        ("K.4-1", .mwlFind, "Cxxx", "Failure", "Failed: Unable to process"),
        ("K.4-1", .mwlFind, "FE00", "Cancel", "Matching terminated due to Cancel request"),
        ("K.4-1", .mwlFind, "0000", "Success", "Matching is complete - No final Identifier is supplied."),
        ("K.4-1", .mwlFind, "FF00", "Pending", "Matches are continuing - Current Match is supplied and any Optional Keys were supported in the same manner as Required Keys."),
        ("K.4-1", .mwlFind, "FF01", "Pending", "Matches are continuing - Warning that one or more Optional Keys were not supported for existence for this Identifier."),
        ("F.7.2-2", .mppsNSet, "0110", "Failure", "Processing Failure"),
        ("F.8.2-2", .mppsNGet, "0001", "Warning", "Requested optional Attributes are not supported"),
        ("H.4.1.2.1.2-1", .filmSessionNCreate, "0000", "Success", "Film session successfully created"),
        ("H.4.1.2.1.2-1", .filmSessionNCreate, "B600", "Warning", "Memory allocation not supported"),
        ("H.4-4", .filmSessionNAction, "0000", "Success", "Film belonging to the film session are accepted for printing; if supported, the Print Job SOP Instance is created"),
        ("H.4-4", .filmSessionNAction, "B601", "Warning", "Film session printing (collation) is not supported"),
        ("H.4-4", .filmSessionNAction, "B602", "Warning", "Film Session SOP Instance hierarchy does not contain Image Box SOP Instances (empty page)"),
        ("H.4-4", .filmSessionNAction, "B604", "Warning", "Image size is larger than image box size, the image has been demagnified."),
        ("H.4-4", .filmSessionNAction, "B609", "Warning", "Image size is larger than the Image Box size. The Image has been cropped to fit."),
        ("H.4-4", .filmSessionNAction, "B60A", "Warning", "Image size or Combined Print Image size is larger than the Image Box size. Image or Combined Print Image has been decimated to fit."),
        ("H.4-4", .filmSessionNAction, "C600", "Failure", "Failed: Film Session SOP Instance hierarchy does not contain Film Box SOP Instances"),
        ("H.4-4", .filmSessionNAction, "C601", "Failure", "Failed: Unable to create Print Job SOP Instance; print queue is full"),
        ("H.4-4", .filmSessionNAction, "C603", "Failure", "Failed: Image size is larger than image box size"),
        ("H.4-4", .filmSessionNAction, "C613", "Failure", "Failed: Combined Print Image size is larger than the Image Box size"),
        ("H.4.2.2.1.2-1", .filmBoxNCreate, "0000", "Success", "Film Box successfully created"),
        ("H.4.2.2.1.2-1", .filmBoxNCreate, "B605", "Warning", "Requested Min Density or Max Density outside of printer's operating range. The printer will use its respective minimum or maximum density value instead."),
        ("H.4.2.2.1.2-1", .filmBoxNCreate, "C616", "Failure", "Failed: There is an existing Film Box that has not been printed and N-ACTION at the Film Session level is not supported. A new Film Box will not be created when a previous Film Box has not been printed."),
        ("H.4-9", .filmBoxNAction, "0000", "Success", "Film accepted for printing; if supported, the Print Job SOP Instance is created"),
        ("H.4-9", .filmBoxNAction, "B603", "Warning", "Film Box SOP Instance hierarchy does not contain Image Box SOP Instances (empty page)"),
        ("H.4-9", .filmBoxNAction, "B604", "Warning", "Image size is larger than image box size, the image has been demagnified."),
        ("H.4-9", .filmBoxNAction, "B609", "Warning", "Image size is larger than the Image Box size. The Image has been cropped to fit."),
        ("H.4-9", .filmBoxNAction, "B60A", "Warning", "Image size or Combined Print Image size is larger than the Image Box size. Image or Combined Print Image has been decimated to fit."),
        ("H.4-9", .filmBoxNAction, "C602", "Failure", "Failed: Unable to create Print Job SOP Instance; print queue is full"),
        ("H.4-9", .filmBoxNAction, "C603", "Failure", "Failed: Image size is larger than image box size"),
        ("H.4-9", .filmBoxNAction, "C613", "Failure", "Failed: Combined Print Image size is larger than the Image Box size"),
        ("H.4.3.1.2.1.2-1", .grayscaleImageBoxNSet, "0000", "Success", "Image successfully stored in Image Box"),
        ("H.4.3.1.2.1.2-1", .grayscaleImageBoxNSet, "B604", "Warning", "Image size larger than image box size, the image has been demagnified."),
        ("H.4.3.1.2.1.2-1", .grayscaleImageBoxNSet, "B605", "Warning", "Requested Min Density or Max Density outside of printer's operating range. The printer will use its respective minimum or maximum density value instead."),
        ("H.4.3.1.2.1.2-1", .grayscaleImageBoxNSet, "B609", "Warning", "Image size is larger than the Image Box size. The Image has been cropped to fit."),
        ("H.4.3.1.2.1.2-1", .grayscaleImageBoxNSet, "B60A", "Warning", "Image size or Combined Print Image size is larger than the Image Box size. The Image or Combined Print Image has been decimated to fit."),
        ("H.4.3.1.2.1.2-1", .grayscaleImageBoxNSet, "C603", "Failure", "Failed: Image size is larger than image box size"),
        ("H.4.3.1.2.1.2-1", .grayscaleImageBoxNSet, "C605", "Failure", "Failed: Insufficient memory in printer to store the image"),
        ("H.4.3.1.2.1.2-1", .grayscaleImageBoxNSet, "C613", "Failure", "Failed: Combined Print Image size is larger than the Image Box size"),
        ("H.4.3.2.2.1.2-1", .colorImageBoxNSet, "B604", "Warning", "Image size larger than image box size, the image has been demagnified."),
        ("H.4.3.2.2.1.2-1", .colorImageBoxNSet, "B609", "Warning", "Image size is larger than the Image Box size. The Image has been cropped to fit."),
        ("H.4.3.2.2.1.2-1", .colorImageBoxNSet, "B60A", "Warning", "Image size or Combined Print Image size is larger than the Image Box size. The Image or Combined Print Image has been decimated to fit."),
        ("H.4.3.2.2.1.2-1", .colorImageBoxNSet, "C603", "Failure", "Failed: Image size is larger than image box size"),
        ("H.4.3.2.2.1.2-1", .colorImageBoxNSet, "C605", "Failure", "Failed: Insufficient memory in printer to store the image"),
        ("H.4.3.2.2.1.2-1", .colorImageBoxNSet, "C613", "Failure", "Failed: Combined Print Image size is larger than the Image Box size"),
        ("H.4.9.2.1.2-1", .presentationLUTNCreate, "0000", "Success", "Presentation LUT successfully created"),
        ("H.4.9.2.1.2-1", .presentationLUTNCreate, "B605", "Warning", "Requested Min Density or Max Density outside of printer's operating range. The printer will use its respective minimum or maximum density value instead."),
    ]

    /// PS3.7 2026a Annex C sections that fix a code: (section, class, title, code).
    static let annexC: [(section: String, statusClass: String, name: String, code: UInt16)] = [
        ("C.1.1", "Success", "Success", 0x0000),
        ("C.3.1", "Cancel", "Cancel", 0xFE00),
        ("C.4.2", "Warning", "Attribute List warning", 0x0107),
        ("C.4.3", "Warning", "Attribute Value out of range", 0x0116),
        ("C.5.6", "Failure", "Refused: SOP Class not supported", 0x0122),
        ("C.5.7", "Failure", "Class-Instance conflict", 0x0119),
        ("C.5.8", "Failure", "Duplicate SOP Instance", 0x0111),
        ("C.5.9", "Failure", "Duplicate invocation", 0x0210),
        ("C.5.10", "Failure", "Invalid argument value", 0x0115),
        ("C.5.11", "Failure", "Invalid Attribute Value", 0x0106),
        ("C.5.12", "Failure", "Invalid SOP Instance", 0x0117),
        ("C.5.13", "Failure", "Missing Attribute", 0x0120),
        ("C.5.14", "Failure", "Missing Attribute Value", 0x0121),
        ("C.5.15", "Failure", "Mistyped argument", 0x0212),
        ("C.5.16", "Failure", "No such argument", 0x0114),
        ("C.5.17", "Failure", "No such Attribute", 0x0105),
        ("C.5.18", "Failure", "No such Event Type", 0x0113),
        ("C.5.19", "Failure", "No such SOP Instance", 0x0112),
        ("C.5.20", "Failure", "No such SOP Class", 0x0118),
        ("C.5.21", "Failure", "Processing Failure", 0x0110),
        ("C.5.22", "Failure", "Resource limitation", 0x0213),
        ("C.5.23", "Failure", "Unrecognized operation", 0x0211),
        ("C.5.24", "Failure", "No such Action Type", 0x0123),
        ("C.5.25", "Failure", "Refused: Not authorized", 0x0124),
    ]


    // MARK: - Tables carried verbatim

    func testServiceTablesMatchPS34_2026a() {
        let services = Set(Self.ps34Rows.map { $0.service })
        XCTAssertEqual(services.count, 10)
        for service in services {
            let expected = Self.ps34Rows.filter { $0.service == service }
                .map { DIMSEServiceStatusRow(code: $0.code, serviceStatus: $0.status, furtherMeaning: $0.meaning) }
            XCTAssertEqual(DIMSEServiceStatusText.rows(for: service), expected, service.rawValue)
            XCTAssertEqual(service.statusTable, Self.ps34Rows.first { $0.service == service }?.table)
        }
        XCTAssertEqual(DIMSEServiceStatusText.rows(for: .dimseN), [])
        XCTAssertEqual(DIMSEStatusService.printManagement.count, 7)
    }

    func testAnnexCSectionsMatchPS37_2026a() {
        XCTAssertEqual(DIMSEServiceStatusText.annexCStatusRows.count, 24)
        XCTAssertEqual(DIMSEServiceStatusText.annexCStatusRows,
                       Self.annexC.map { DIMSEAnnexCStatusRow(section: $0.section, code: $0.code,
                                                              statusClass: $0.statusClass, name: $0.name) })
    }

    // MARK: - DIMSEStatus.description (D73, D79, D82)

    func testDescriptionUsesThe2026aNames() {
        XCTAssertEqual(DIMSEStatus.from(0xA900).description, "Error: Data Set does not match SOP Class (0xA900)")
        XCTAssertEqual(DIMSEStatus.from(0x0110).description, "Processing Failure (0x0110)")
        XCTAssertEqual(DIMSEStatus.from(0xA801).description, "Refused: Move Destination unknown (0xA801)")
        XCTAssertEqual(DIMSEStatus.from(0xA702).description, "Refused: Out of resources (0xA702)")
        // Every DIMSE-N code PS3.7 Annex C fixes is named, none prints "Unknown status".
        for row in Self.annexC {
            let text = DIMSEStatus.from(row.code).description
            XCTAssertFalse(text.hasPrefix("Unknown status"), text)
        }
        XCTAssertEqual(DIMSEStatus.from(0x0117).description, "Invalid SOP Instance (0x0117)")
        XCTAssertEqual(DIMSEStatus.from(0x0210).description, "Duplicate invocation (0x0210)")
        XCTAssertEqual(DIMSEStatus.from(0x0211).description, "Unrecognized operation (0x0211)")
        XCTAssertEqual(DIMSEStatus.from(0x0212).description, "Mistyped argument (0x0212)")
        XCTAssertEqual(DIMSEStatus.from(0x0106).description, "Invalid Attribute Value (0x0106)")
        XCTAssertEqual(DIMSEStatus.from(0x0107).description, "Attribute List warning (0x0107)")
        XCTAssertEqual(DIMSEStatus.from(0x0999).description, "Unknown status (0x0999)")
    }

    func testServiceDescriptionFallsBackToAnnexC() {
        XCTAssertEqual(DIMSEStatus.from(0x0106).description(for: .dimseN), "Failure (0x0106): Invalid Attribute Value")
        XCTAssertEqual(DIMSEStatus.from(0x0110).description(for: .mppsNSet), "Failure (0x0110): Processing Failure")
        XCTAssertEqual(DIMSEStatus.from(0x0000).description(for: .mppsNSet), "Success (0x0000): Success")
        XCTAssertEqual(DIMSEStatus.from(0xA900).description(for: .mwlFind),
                       "Failure (0xA900): Error: Data Set does not match SOP Class")
        XCTAssertEqual(DIMSEStatus.from(0xC001).description(for: .mwlFind), "Failure (0xC001): Failed: Unable to process")
        XCTAssertEqual(DIMSEStatus.from(0x0122).description(for: .cStore),
                       "Failure (0x0122): Refused: SOP Class not supported")
        XCTAssertEqual(DIMSEStatus.from(0xC603).description(for: .filmBoxNAction),
                       "Failure (0xC603): Failed: Image size is larger than image box size")
        XCTAssertEqual(DIMSEStatus.from(0xB604).description(for: .grayscaleImageBoxNSet),
                       "Warning (0xB604): Image size larger than image box size, the image has been demagnified.")
    }

    // MARK: - Print (D91, D93)

    func testPrintOperationFailedNamesAnnexHStatus() {
        let error = DICOMNetworkError.printOperationFailed(DIMSEStatus.from(0xC603), detail: nil)
        XCTAssertEqual(error.description, "Print operation failed: Failure (0xC603): Failed: Image size is larger than image box size")
        let queue = DICOMNetworkError.printOperationFailed(DIMSEStatus.from(0xC602), detail: "OUT OF FILM")
        XCTAssertEqual(queue.description,
                       "Print operation failed: Failure (0xC602): Failed: Unable to create Print Job SOP Instance; print queue is full — OUT OF FILM")
        XCTAssertEqual(DICOMNetworkError.printOperationFailed(DIMSEStatus.from(0x0106), detail: nil).description,
                       "Print operation failed: Failure (0x0106): Invalid Attribute Value")
    }

    func testPrintSCPStatusExplanationsAreVerbatim() {
        let expected: [PrintSCPStatus: String] = [
            .warningMemoryAllocation: "Memory allocation not supported",
            .warningImageDemagnified: "Image size is larger than image box size, the image has been demagnified.",
            .warningMinMaxDensityOutOfRange: "Requested Min Density or Max Density outside of printer's operating range. The printer will use its respective minimum or maximum density value instead.",
            .warningImageCropped: "Image size is larger than the Image Box size. The Image has been cropped to fit.",
            .imageLargerThanImageBox: "Failed: Image size is larger than image box size",
            .insufficientMemory: "Failed: Insufficient memory in printer to store the image",
            .combinedImageLargerThanImageBox: "Failed: Combined Print Image size is larger than the Image Box size",
            .filmSessionPrinting: "Failed: Film Session SOP Instance hierarchy does not contain Film Box SOP Instances",
            .printQueueFull: "Failed: Unable to create Print Job SOP Instance; print queue is full",
            .processingFailure: "Processing Failure",
            .invalidObjectInstance: "Invalid SOP Instance",
            .classInstanceConflict: "Class-Instance conflict",
            .sopClassNotSupported: "Refused: SOP Class not supported",
            .success: "Success",
        ]
        for (status, text) in expected {
            XCTAssertEqual(status.explanation, text, String(format: "0x%04X", status.rawValue))
        }
        for status in PrintSCPStatus.allCases {
            XCTAssertFalse(status.explanation.hasPrefix("Status 0x"), String(format: "0x%04X unnamed", status.rawValue))
        }
    }

    // MARK: - MPPS (D83, D84, D86, D87)

    func testMPPSFailureIsNotWordedAsAStore() {
        let nSet = DICOMNetworkError.mppsOperationFailed(operation: "N-SET", status: DIMSEStatus.from(0x0110),
                                                         errorComment: nil, errorID: 0xA710)
        XCTAssertEqual(nSet.description,
                       "MPPS N-SET failed: Failure (0x0110): Processing Failure — Error ID A710H: Performed Procedure Step Object may no longer be updated")
        XCTAssertFalse(nSet.description.contains("Store failed"))
        let nCreate = DICOMNetworkError.mppsOperationFailed(operation: "N-CREATE", status: DIMSEStatus.from(0x0106),
                                                            errorComment: "Bad modality", errorID: nil)
        XCTAssertEqual(nCreate.description,
                       "MPPS N-CREATE failed: Failure (0x0106): Invalid Attribute Value — Error Comment: Bad modality")
        XCTAssertEqual(nCreate.category, .permanent)
        XCTAssertFalse(nCreate.isRetryable)
    }

    func testCodedEntryExampleIsTableD1() {
        XCTAssertEqual(MPPSCodedEntry.parseErrorMessage(option: "--discontinuation-reason"),
                       "--discontinuation-reason must be CODE|SCHEME|MEANING, e.g. \"110513|DCM|Discontinued for unspecified reason\"")
    }

    private func step(modality: String?) -> MPPSProcedureStep {
        MPPSProcedureStep(sopInstanceUID: "1.2.3", status: .inProgress, studyInstanceUID: "1.2.3.4",
                          startDateTime: Date(), modality: modality, procedureStepID: "PPS1")
    }

    func testNCreateRequiresModality() {
        for modality in [nil, "", "  "] as [String?] {
            XCTAssertThrowsError(try DICOMMPPSService.validate(step(modality: modality), for: .nCreate)) { error in
                guard case DICOMNetworkError.invalidState(let message) = error else { return XCTFail("\(error)") }
                XCTAssertTrue(message.contains("(0008,0060)"), message)
            }
        }
        XCTAssertNoThrow(try DICOMMPPSService.validate(step(modality: "CT"), for: .nCreate))
    }

    /// PS3.4 F.7.2.1.1 note: (0040,0281) is created zero-length at N-CREATE.
    func testNCreateCreatesZeroLengthDiscontinuationReason() {
        let data = DICOMMPPSService.buildMPPSAttributes(procedureStep: step(modality: "CT"),
                                                        transferSyntax: "1.2.840.10008.1.2.1")
        let header = Data([0x40, 0x00, 0x81, 0x02, 0x53, 0x51, 0x00, 0x00])  // (0040,0281) SQ
        guard let r = data.range(of: header) else { return XCTFail("(0040,0281) not created") }
        let length = data[r.upperBound..<(r.upperBound + 4)]
        XCTAssertTrue(length == Data([0, 0, 0, 0]) || length == Data([0xFF, 0xFF, 0xFF, 0xFF]),
                      "zero-length (or empty undefined-length) sequence")
        if length == Data([0xFF, 0xFF, 0xFF, 0xFF]) {
            XCTAssertEqual(data[(r.upperBound + 4)..<(r.upperBound + 8)], Data([0xFE, 0xFF, 0xDD, 0xE0]), "no items")
        }
    }
}
