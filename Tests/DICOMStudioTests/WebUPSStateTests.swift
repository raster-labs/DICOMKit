// WebUPSStateTests.swift
// DICOMStudioTests
//
// D259 / P-STUDIO-UPS-STATE-RAW: `WebUPSState` names the DICOMWeb UPSState enum from inside
// DICOMStudio, and Studio's former `UPSState` enum is now a deprecated alias of it, so the
// raw values are the PS3.3 2026a Table C.30.1-1 words (SCHEDULED, IN PROGRESS, CANCELED, COMPLETED).

import Testing
@testable import DICOMStudio
import Foundation

@Suite("WebUPSState (DICOMWeb.UPSState reached from DICOMStudio)")
struct WebUPSStateTests {

    /// PS3.3 2026a Table C.30.1-1, Procedure Step State (0074,1000) Enumerated Values
    /// (extracted from part03_2026a.xml by script, 2026-10-06).
    static let tableC3011: Set<String> = ["SCHEDULED", "IN PROGRESS", "CANCELED", "COMPLETED"]

    @Test("WebUPSState is the DICOMWeb enum: its raw values are the Table C.30.1-1 words")
    func aliasIsTheWebEnum() {
        #expect(Set(WebUPSState.allCases.map(\.rawValue)) == Self.tableC3011)
        #expect(WebUPSState.inProgress.rawValue == "IN PROGRESS")
        #expect(WebUPSState.canceled.rawValue == "CANCELED")
        for state in WebUPSState.allCases { #expect(state.dicomTerm == state.rawValue) }
        // The engine's transition rule (PS3.4 Table CC.1.1-2) is reachable through the alias.
        #expect(WebUPSState.scheduled.canTransition(to: .inProgress))
        #expect(!WebUPSState.scheduled.canTransition(to: .completed))
        for state in WebUPSState.allCases { #expect(state.allowedTransitions == state.validTransitions) }
    }

    @Test("Values stored with the retired Studio raw values IN_PROGRESS / CANCELLED still decode")
    func legacyRawValuesDecode() {
        #expect(WebUPSState(legacyRawValue: "IN_PROGRESS") == .inProgress)
        #expect(WebUPSState(legacyRawValue: "CANCELLED") == .canceled)
        #expect(WebUPSState(legacyRawValue: "SCHEDULED") == .scheduled)
        #expect(WebUPSState(legacyRawValue: "COMPLETED") == .completed)
        for state in WebUPSState.allCases { #expect(WebUPSState(legacyRawValue: state.rawValue) == state) }
        #expect(WebUPSState(legacyRawValue: "DONE") == nil)
        // The synthesized raw-value initializer knows only the standard words.
        #expect(WebUPSState(rawValue: "IN_PROGRESS") == nil)
    }

    @Test("Deprecated names keep compiling: UPSState is WebUPSState, .cancelled is .canceled")
    @available(*, deprecated)
    func deprecatedAliases() {
        let state: UPSState = .cancelled
        #expect(state == WebUPSState.canceled)
        #expect(UPSState.inProgress.rawValue == "IN PROGRESS")
        #expect(UPSState.allCases.count == 4)
    }
}
