// WebUPSState.swift
// DICOMStudio
// NEMA-verified: 2026a, checked 2026-10-06 — the four Procedure Step State (0074,1000) words of the DICOMWeb enum this alias names diffed against PS3.3 2026a Table C.30.1-1 Enumerated Values (SCHEDULED, IN PROGRESS, CANCELED, COMPLETED — 4/4) by WebUPSStateTests; Studio's `UPSState` is now a deprecated alias of this enum (P-STUDIO-UPS-STATE-RAW), so its raw values are those words; the retired Studio spellings IN_PROGRESS / CANCELLED decode through `init?(legacyRawValue:)`; `allowedTransitions` is DICOMWeb's `validTransitions` (PS3.4 2026a Table CC.1.1-2)
//
// DICOM Studio — `DICOMWeb.UPSState` named from inside DICOMStudio (D259, P-STUDIO-UPS-STATE-RAW)
// Reference: DICOM PS3.3 C.30.1 (Procedure Step State), PS3.4 Annex CC, PS3.18 11.7

import DICOMWeb

/// The DICOMWeb `UPSState` enum: the Procedure Step State (0074,1000) Enumerated Values of
/// PS3.3 2026a Table C.30.1-1 as raw values — SCHEDULED, IN PROGRESS, COMPLETED, CANCELED (D259).
/// DICOM Studio's UPS screens use this enum; the former Studio enum `UPSState` is a deprecated
/// alias of it (P-STUDIO-UPS-STATE-RAW).
///
/// The DICOMWeb module exports a namespace enum named `DICOMWeb`, so `DICOMWeb.UPSState` resolves
/// to that enum (and fails), and DICOMStudio's deprecated `UPSState` alias wins every unqualified
/// lookup; the module selector `DICOMWeb::UPSState` names the engine's enum. (D259 reached it
/// through `Workitem.State`; that route cannot be public or extended.)
public typealias WebUPSState = DICOMWeb::UPSState

// MARK: - Studio presentation

extension DICOMWeb::UPSState {
    /// Human-readable display name (the PS3.3 2026a Table C.30.1-1 word in title case).
    public var displayName: String {
        switch self {
        case .scheduled:  return "Scheduled"
        case .inProgress: return "In Progress"
        case .completed:  return "Completed"
        case .canceled:   return "Canceled"
        }
    }

    /// The Procedure Step State (0074,1000) term of PS3.3 2026a Table C.30.1-1 — the raw value.
    public var dicomTerm: String { rawValue }

    /// SF Symbol for this state.
    public var sfSymbol: String {
        switch self {
        case .scheduled:  return "clock"
        case .inProgress: return "arrow.triangle.2.circlepath"
        case .completed:  return "checkmark.circle.fill"
        case .canceled:   return "xmark.circle"
        }
    }

    /// The target states a Change Workitem State request (PS3.18 11.7) may ask for from this
    /// state: DICOMWeb's `validTransitions`, PS3.4 2026a Table CC.1.1-2 (SCHEDULED → IN PROGRESS;
    /// IN PROGRESS → COMPLETED or CANCELED; final states → none; SCHEDULED is never a target, C303H;
    /// SCHEDULED → CANCELED is refused with C310H).
    public var allowedTransitions: [WebUPSState] { validTransitions }

    /// The Studio spelling of CANCELED, kept so older code compiles.
    @available(*, deprecated, renamed: "canceled",
               message: "PS3.3 Table C.30.1-1 spells the Procedure Step State CANCELED")
    public static var cancelled: WebUPSState { .canceled }

    /// Decoding shim for values persisted by the former Studio enum: its raw values were
    /// `IN_PROGRESS` and `CANCELLED`, which are not PS3.3 2026a Table C.30.1-1 words. Accepts those
    /// two and every current raw value (SCHEDULED, IN PROGRESS, COMPLETED, CANCELED); nil otherwise.
    public init?(legacyRawValue raw: String) {
        switch raw {
        case "IN_PROGRESS": self = .inProgress
        case "CANCELLED":   self = .canceled
        default:
            guard let state = WebUPSState(rawValue: raw) else { return nil }
            self = state
        }
    }
}
