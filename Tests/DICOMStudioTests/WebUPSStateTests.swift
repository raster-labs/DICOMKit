// WebUPSStateTests.swift
// DICOMStudioTests
//
// D259: `WebUPSState` names the DICOMWeb UPSState enum from inside DICOMStudio (whose own
// `UPSState` shadows it), and the two enums map onto each other by their PS3.3 2026a
// Table C.30.1-1 word (SCHEDULED, IN PROGRESS, CANCELED, COMPLETED).

import Testing
@testable import DICOMStudio
import Foundation

@Suite("WebUPSState (DICOMWeb.UPSState reached from DICOMStudio)")
struct WebUPSStateTests {

    /// PS3.3 2026a Table C.30.1-1, Procedure Step State (0074,1000) Enumerated Values.
    static let tableC3011: Set<String> = ["SCHEDULED", "IN PROGRESS", "CANCELED", "COMPLETED"]

    @Test("WebUPSState is the DICOMWeb enum: its raw values are the Table C.30.1-1 words, not the Studio spellings")
    func aliasIsTheWebEnum() {
        #expect(Set(WebUPSState.allCases.map(\.rawValue)) == Self.tableC3011)
        #expect(WebUPSState.inProgress.rawValue == "IN PROGRESS")
        #expect(WebUPSState.canceled.rawValue == "CANCELED")
        // The Studio enum keeps its local raw spellings (P-STUDIO-UPS-STATE-RAW not approved).
        #expect(UPSState.inProgress.rawValue == "IN_PROGRESS")
        #expect(UPSState.cancelled.rawValue == "CANCELLED")
        // The engine's transition rule (PS3.4 Table CC.1.1-2) is reachable through the alias.
        #expect(WebUPSState.scheduled.canTransition(to: .inProgress))
        #expect(!WebUPSState.scheduled.canTransition(to: .completed))
    }

    @Test("Studio UPSState <-> WebUPSState round-trips through the Table C.30.1-1 word (4/4)")
    func mappingRoundTrips() {
        #expect(UPSState.allCases.count == 4 && WebUPSState.allCases.count == 4)
        for state in UPSState.allCases {
            #expect(state.web.rawValue == state.dicomTerm, Comment(rawValue: state.rawValue))
            #expect(UPSState(web: state.web) == state, Comment(rawValue: state.rawValue))
        }
        for web in WebUPSState.allCases {
            #expect(UPSState(web: web).web == web, Comment(rawValue: web.rawValue))
        }
    }
}
