import XCTest
@testable import DICOMWeb

/// Pins the option rules DICOMWeb shares with dicom-wado and DICOM Studio to the DICOM 2026a
/// text: PS3.18 11.7.1.4 / PS3.4 Table CC.1.1-2 (UPS Change State targets, D255).
final class DICOMwebOptionRulesTests: XCTestCase {

    // MARK: - UPS Change Workitem State targets (PS3.18 2026a 11.7.1.4; PS3.4 Table CC.1.1-2)

    func testChangeStateTargetsAreTheThreeOf11_7_1_4() {
        XCTAssertEqual(UPSState.changeStateTargets.map(\.rawValue), ["IN PROGRESS", "COMPLETED", "CANCELED"])
        XCTAssertFalse(UPSState.scheduled.isChangeStateTarget)
        XCTAssertTrue(UPSState.inProgress.isChangeStateTarget)
        XCTAssertTrue(UPSState.completed.isChangeStateTarget)
        XCTAssertTrue(UPSState.canceled.isChangeStateTarget)
        // Table CC.1.1-2: every target is reachable by a valid transition from some state.
        for target in UPSState.changeStateTargets {
            XCTAssertTrue(UPSState.allCases.contains { $0.canTransition(to: target) }, target.rawValue)
        }
    }

    func testScheduledRefusalIsTheSharedText() {
        XCTAssertEqual(UPSState.scheduled.changeStateRefusal,
                       "SCHEDULED is not a Change Workitem State target: PS3.18 2026a 11.7.1.4 "
                       + "allows IN PROGRESS, COMPLETED or CANCELED, and PS3.4 2026a Table CC.1.1-2 refuses a change "
                       + "to SCHEDULED (C303H)")
        for target in UPSState.changeStateTargets {
            XCTAssertNil(target.changeStateRefusal)
        }
        XCTAssertEqual(UPSState.unknownStateRefusal("DONE"),
                       "Invalid state: DONE. Valid states: IN PROGRESS (or IN_PROGRESS), COMPLETED, "
                       + "CANCELED (PS3.18 2026a 11.7.1.4)")
    }

    func testOptionValueAcceptsTheStandardSpellingAndTheCLISpellings() {
        XCTAssertEqual(UPSState(optionValue: "IN PROGRESS"), .inProgress)
        XCTAssertEqual(UPSState(optionValue: " in progress "), .inProgress)
        XCTAssertEqual(UPSState(optionValue: "IN_PROGRESS"), .inProgress)
        XCTAssertEqual(UPSState(optionValue: "INPROGRESS"), .inProgress)
        XCTAssertEqual(UPSState(optionValue: "SCHEDULED"), .scheduled)
        XCTAssertEqual(UPSState(optionValue: "completed"), .completed)
        XCTAssertEqual(UPSState(optionValue: "CANCELED"), .canceled)
        XCTAssertNil(UPSState(optionValue: "CANCELLED"))
        XCTAssertNil(UPSState(optionValue: ""))
    }

    func testChangeStateTargetRefusesScheduledAndUnknownValues() throws {
        XCTAssertEqual(try UPSState.changeStateTarget(optionValue: "IN PROGRESS"), .inProgress)
        XCTAssertEqual(try UPSState.changeStateTarget(optionValue: "completed"), .completed)
        XCTAssertEqual(try UPSState.changeStateTarget(optionValue: "CANCELED"), .canceled)
        XCTAssertThrowsError(try UPSState.changeStateTarget(optionValue: "SCHEDULED")) { error in
            let refusal = error as? DICOMwebOptionRefusal
            XCTAssertEqual(refusal?.kind, .refused)
            XCTAssertEqual(refusal?.exitCode, 1)
            XCTAssertEqual(refusal?.message, UPSState.scheduled.changeStateRefusal)
            XCTAssertEqual("\(error)", UPSState.scheduled.changeStateRefusal)   // what the CLI prints
            XCTAssertEqual(error.localizedDescription, UPSState.scheduled.changeStateRefusal)
        }
        XCTAssertThrowsError(try UPSState.changeStateTarget(optionValue: "DONE")) { error in
            XCTAssertEqual((error as? DICOMwebOptionRefusal)?.message, UPSState.unknownStateRefusal("DONE"))
        }
        XCTAssertEqual(DICOMwebOptionRefusal(.usage, "x").exitCode, 64)
    }
}
