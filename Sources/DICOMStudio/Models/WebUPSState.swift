// WebUPSState.swift
// DICOMStudio
// NEMA-verified: 2026a, checked 2026-10-06 — the four Procedure Step State (0074,1000) words of the DICOMWeb enum this alias names, and the Studio UPSState ↔ WebUPSState mapping, diffed against PS3.3 2026a Table C.30.1-1 Enumerated Values (SCHEDULED, IN PROGRESS, CANCELED, COMPLETED — 4/4)
//
// DICOM Studio — `DICOMWeb.UPSState` named from inside DICOMStudio (D259)
// Reference: DICOM PS3.3 C.30.1 (Procedure Step State), PS3.4 Annex CC, PS3.18 11.7

import DICOMWeb

/// Carrier of a UPS state; `Workitem` conforms with `State` inferred from its `state` property.
///
/// The DICOMWeb module exports a namespace enum named `DICOMWeb`, so `DICOMWeb.UPSState` resolves to
/// that enum (and fails), while DICOMStudio's own `UPSState` wins every unqualified lookup. The
/// engine's enum is reached through associated-type inference instead: `Workitem.state` is declared
/// as the DICOMWeb enum, so `Workitem.State` is that enum.
protocol UPSStateCarrier {
    associatedtype State
    var state: State { get }
}

extension Workitem: UPSStateCarrier {}

/// The DICOMWeb `UPSState` enum (PS3.3 Table C.30.1-1 words as raw values: SCHEDULED, IN PROGRESS,
/// COMPLETED, CANCELED), usable from DICOMStudio beside the Studio-local `UPSState` (D259).
/// Both types stay: the Studio enum keeps its local raw spellings (P-STUDIO-UPS-STATE-RAW, not approved).
typealias WebUPSState = Workitem.State

extension UPSState {
    /// The DICOMWeb state for this Studio case: the same PS3.3 Table C.30.1-1 word (`dicomTerm`).
    var web: WebUPSState {
        switch self {
        case .scheduled:  return .scheduled
        case .inProgress: return .inProgress
        case .completed:  return .completed
        case .cancelled:  return .canceled
        }
    }

    /// The Studio case for a DICOMWeb state (PS3.3 Table C.30.1-1: four words, one case each).
    init(web: WebUPSState) {
        switch web {
        case .scheduled:  self = .scheduled
        case .inProgress: self = .inProgress
        case .completed:  self = .completed
        case .canceled:   self = .cancelled
        }
    }
}
