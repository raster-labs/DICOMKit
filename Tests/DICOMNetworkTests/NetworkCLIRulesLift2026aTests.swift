//
// NetworkCLIRulesLift2026aTests.swift
// DICOMNetworkTests
//
// CLI-local rules lifted into DICOMNetwork for the DICOMStudio CLI Workshop
// (2026-10-06): D262 (C-MOVE / C-GET final response), D263 (dicom-mpps option
// rules), D264 (dicom-mwl --sps-status). Each pinned to its DICOM 2026a reference.
//

import XCTest
import DICOMCore
@testable import DICOMNetwork

final class NetworkCLIRulesLift2026aTests: XCTestCase {

    // MARK: - D262: PS3.4 Tables C.4-2 / C.4-3, PS3.7 Table 9.3-10, (0008,0058)

    func testRetrieveFinalResponseFailure() {
        let progress = RetrieveProgress(completed: 1, failed: 1, warning: 0)
        let result = RetrieveResult(status: .from(0xB000), progress: progress, failedSOPInstanceUIDs: ["1.2.3", "1.2.4"])
        let report = NetworkConsole.retrieveFinalResponse(result, service: .cMove)
        let described = DIMSEServiceStatusText.describe(.from(0xB000), service: .cMove)
        let counts = "Number of Completed Sub-operations: 1, Number of Failed Sub-operations: 1, "
            + "Number of Warning Sub-operations: 0"
        XCTAssertEqual(report.lines, [
            "Failed SOP Instance UID List (0008,0058), 2 UID(s):", "  1.2.3", "  1.2.4",
            "Final C-MOVE response: \(described) — \(counts)",
        ])
        XCTAssertEqual(report.failure,
                       "C-MOVE final response \(described) (\(counts)); Failed SOP Instance UID List (0008,0058): 1.2.3, 1.2.4")
        // Table C.4-2 B000 "Sub-operations Complete - One or more Failures".
        XCTAssertTrue(described.contains("One or more Failures"), described)
    }

    func testRetrieveFinalResponseSuccessAndFailedCounter() {
        let ok = RetrieveResult(status: .success, progress: RetrieveProgress(completed: 4))
        XCTAssertEqual(NetworkConsole.retrieveFinalResponse(ok, service: .cGet).lines, [])
        XCTAssertNil(NetworkConsole.retrieveFinalResponse(ok, service: .cGet).failure)
        // 0000 with a failed sub-operation is not success (PS3.4 C.4.3.2.1); no UID list.
        let notOK = RetrieveResult(status: .success, progress: RetrieveProgress(completed: 3, failed: 1))
        let report = NetworkConsole.retrieveFinalResponse(notOK, service: .cGet)
        XCTAssertEqual(report.lines.count, 1)
        XCTAssertTrue(report.lines[0].hasPrefix("Final C-GET response: "), report.lines[0])
        XCTAssertTrue(report.failure?.hasPrefix("C-GET final response ") ?? false)
        XCTAssertFalse(report.failure?.contains("(0008,0058)") ?? true)
    }

    // MARK: - D263: PS3.3 Tables C.4-14 / C.2-3, PS3.5 Table 6.2-1 DA

    func testMPPSStatusWords() {
        XCTAssertEqual(DICOMMPPSService.parseStatus("IN PROGRESS"), .inProgress)
        XCTAssertEqual(DICOMMPPSService.parseStatus("in_progress"), .inProgress)
        XCTAssertEqual(DICOMMPPSService.parseStatus("InProgress"), .inProgress)
        XCTAssertEqual(DICOMMPPSService.parseStatus("completed"), .completed)
        XCTAssertEqual(DICOMMPPSService.parseStatus("DISCONTINUED"), .discontinued)
        XCTAssertNil(DICOMMPPSService.parseStatus("SCHEDULED"))
        XCTAssertEqual(DICOMMPPSService.invalidStatusMessage,
                       "Invalid status. Use 'IN PROGRESS', 'COMPLETED', or 'DISCONTINUED'")
        // The three Enumerated Values of (0040,0252) are MPPSStatus' raw values.
        XCTAssertEqual(Set([MPPSStatus.inProgress, .completed, .discontinued].map(\.rawValue)),
                       ["IN PROGRESS", "COMPLETED", "DISCONTINUED"])
    }

    func testMPPSPatientSexAndBirthDate() {
        XCTAssertEqual(DICOMMPPSService.patientSexEnumeratedValues, ["M", "F", "O"])
        XCTAssertEqual(DICOMMPPSService.canonicalPatientSex(" f "), "F")
        XCTAssertNil(DICOMMPPSService.canonicalPatientSex("U"))
        XCTAssertEqual(DICOMMPPSService.patientSexErrorMessage("U"),
                       "--patient-sex must be one of M, F, O (Patient's Sex (0010,0040) Enumerated Values, PS3.3 Table C.2-3), got 'U'")
        XCTAssertTrue(DICOMMPPSService.isValidBirthDate("19800131"))
        XCTAssertFalse(DICOMMPPSService.isValidBirthDate("1980-01-31"))
        XCTAssertFalse(DICOMMPPSService.isValidBirthDate("1980013"))
        XCTAssertFalse(DICOMMPPSService.isValidBirthDate("１９８００１３１"))
        XCTAssertEqual(DICOMMPPSService.birthDateErrorMessage("x"),
                       "--patient-birth-date must be YYYYMMDD (VR DA, PS3.5 Table 6.2-1), got 'x'")
    }

    func testMPPSWarningLine() {
        let warning = DIMSEStatus.from(0x0107)
        XCTAssertEqual(DICOMMPPSService.warningLine(warning, operation: "N-SET"),
                       "warning: SCP completed the N-SET with "
                       + DIMSEServiceStatusText.describe(warning, service: .mppsNSet)
                       + " — attributes may have been coerced or dropped\n")
        XCTAssertEqual(DICOMMPPSService.describeStatus(warning, operation: "N-CREATE"),
                       DIMSEServiceStatusText.describe(warning, service: .dimseN))
    }

    // MARK: - D264: PS3.3 Table C.4-10 (0040,0020) Defined Terms

    func testSPSStatusDefinedTermsAndWarning() {
        XCTAssertEqual(WorklistQueryKeys.scheduledProcedureStepStatusDefinedTerms,
                       ["SCHEDULED", "ARRIVED", "READY", "STARTED", "DEPARTED"])
        XCTAssertNil(WorklistQueryKeys.spsStatusWarning(nil))
        XCTAssertNil(WorklistQueryKeys.spsStatusWarning(""))
        XCTAssertNil(WorklistQueryKeys.spsStatusWarning("READY"))
        XCTAssertEqual(WorklistQueryKeys.spsStatusWarning("IN PROGRESS"),
                       "warning: --sps-status 'IN PROGRESS' is not a Scheduled Procedure Step Status Defined Term "
                       + "(PS3.3 Table C.4-10: SCHEDULED, ARRIVED, READY, STARTED, DEPARTED); "
                       + "it is sent as given and will match only an SCP that uses that private term\n")
    }
}
