import Foundation

// NEMA-verified: 2026a, checked 2026-09-28 — event content read against PS3.4 2026a Table CC.2.4-1 (audit report P-EVENT, approved by the owner 2026-09-28 and applied in df9d92b)
// NEMA-verified: 2026a, checked 2026-10-06 — re-diffed by script against PS3.4 2026a Table CC.2.4-1 (D254): `eventTypeID` maps the 7 cases onto the table's 5 Event Type IDs (1 UPS State Report incl. `completed`/`canceled`, 2 UPS Cancel Requested, 3 UPS Progress Report, 4 SCP Status Change, 5 UPS Assigned; `init(eventTypeID:)` decodes all 5); every `toDICOMJSON` carries Event Type ID (0000,1002) and only tags of its table row (State Report 4/4 incl. Type 1 (0074,1000) and (0040,4041); Progress Report 6 of 7 nested inside Procedure Step Progress Information Sequence (0074,1002); Cancel Requested 4 of 5, the Type 1 Requesting AE (0074,1236) is added by the origin server; Assigned 2 of 3); the raw-string case names are DICOMKit identifiers, not wire values, and no bare-name keys or Transaction UID are written
// MARK: - UPSEventType

/// UPS Event Type
///
/// Defines the types of events that can be generated for UPS workitems.
///
/// Reference: PS3.18 Section 8.10 - Notifications; PS3.4 Annex CC.2.4 - Report a Change in UPS Status (Table CC.2.4-1)
public enum UPSEventType: String, Sendable, Codable, CaseIterable {
    /// UPS State Report (Event Type ID 1) - Procedure Step State or Input Readiness State changed
    case stateReport = "StateReport"
    
    /// UPS Progress Report (Event Type ID 3) - Procedure Step Progress Information changed
    case progressReport = "ProgressReport"
    
    /// UPS Cancel Requested (Event Type ID 2) - an AE requested cancellation
    case cancelRequested = "CancelRequested"
    
    /// UPS Assigned (Event Type ID 5) - scheduled station or human performer assigned
    case assigned = "Assigned"
    
    /// SCP Status Change (Event Type ID 4) - the origin server restarted or is going down
    case scpStatusChange = "SCPStatusChange"
    
    /// Completed - a UPS State Report (Event Type ID 1) whose state is COMPLETED
    case completed = "Completed"
    
    /// Canceled - a UPS State Report (Event Type ID 1) whose state is CANCELED
    case canceled = "Canceled"
    
    /// The Event Type ID (0000,1002) of PS3.4 Table CC.2.4-1. The raw string values are
    /// DICOMKit identifiers; on the wire an Event Report is identified by this number.
    public var eventTypeID: Int {
        switch self {
        case .stateReport, .completed, .canceled: return 1
        case .cancelRequested: return 2
        case .progressReport: return 3
        case .scpStatusChange: return 4
        case .assigned: return 5
        }
    }
    
    /// The event type for an Event Type ID (0000,1002) of PS3.4 Table CC.2.4-1
    public init?(eventTypeID: Int) {
        switch eventTypeID {
        case 1: self = .stateReport
        case 2: self = .cancelRequested
        case 3: self = .progressReport
        case 4: self = .scpStatusChange
        case 5: self = .assigned
        default: return nil
        }
    }
    
    /// The Event Type ID (0000,1002) attribute for the Event Report payload
    var eventTypeIDAttribute: [String: Any] {
        ["vr": "US", "Value": [eventTypeID]]
    }
}

/// Event Type ID (0000,1002), the command element that identifies an N-EVENT-REPORT
/// (PS3.7 Table E.1-1); the payload of a PS3.18 8.10.5 Send Event Report carries it.
let eventTypeIDTag = "00001002"

// MARK: - UPSEvent Protocol

/// Base protocol for all UPS events
///
/// Events are generated when workitem state or properties change and are
/// delivered to subscribers via WebSocket or long polling.
public protocol UPSEvent: Sendable {
    /// The type of event
    var eventType: UPSEventType { get }
    
    /// The UID of the workitem this event is about
    var workitemUID: String { get }
    
    /// Transaction UID for this event
    var transactionUID: String? { get }
    
    /// Timestamp when the event was generated
    var timestamp: Date { get }
    
    /// Converts the event to a DICOM JSON dictionary
    func toDICOMJSON() -> [String: Any]
}

// MARK: - UPSStateReportEvent

/// Event generated when a workitem's state changes
///
/// Reference: PS3.4 Table CC.2.4-1 - UPS State Report (Event Type ID 1)
public struct UPSStateReportEvent: UPSEvent, Sendable, Equatable {
    public let eventType: UPSEventType = .stateReport
    public let workitemUID: String
    public let transactionUID: String?
    public let timestamp: Date
    
    /// Previous state
    public let previousState: UPSState
    
    /// New state
    public let newState: UPSState
    
    /// Reason For Cancellation (0074,1238), Type 3 in a State Report
    public let reason: String?
    
    /// Input Readiness State (0040,4041), Type 1 in a State Report (PS3.4 Table CC.2.4-1)
    public let inputReadinessState: InputReadinessState
    
    /// Procedure Step Discontinuation Reason Code Sequence (0074,100E), Type 3
    public let discontinuationReasonCodes: [CodedEntry]?
    
    /// Creates a state report event
    public init(
        workitemUID: String,
        transactionUID: String? = nil,
        timestamp: Date = Date(),
        previousState: UPSState,
        newState: UPSState,
        reason: String? = nil,
        inputReadinessState: InputReadinessState = .ready,
        discontinuationReasonCodes: [CodedEntry]? = nil
    ) {
        self.workitemUID = workitemUID
        self.transactionUID = transactionUID
        self.timestamp = timestamp
        self.previousState = previousState
        self.newState = newState
        self.reason = reason
        self.inputReadinessState = inputReadinessState
        self.discontinuationReasonCodes = discontinuationReasonCodes
    }
    
    /// The UPS State Report Event Report Information of PS3.4 Table CC.2.4-1 (Event Type ID 1):
    /// Procedure Step State, Input Readiness State, and the optional cancellation reason and
    /// code. The Transaction UID is the access lock and is never part of an Event Report.
    public func toDICOMJSON() -> [String: Any] {
        var json: [String: Any] = [
            eventTypeIDTag: eventType.eventTypeIDAttribute,
            UPSTag.procedureStepState: ["vr": "CS", "Value": [newState.rawValue]],
            UPSTag.inputReadinessState: ["vr": "CS", "Value": [inputReadinessState.rawValue]]
        ]
        if let reason = reason {
            json[UPSTag.reasonForCancellation] = ["vr": "LT", "Value": [reason]]
        }
        if let codes = discontinuationReasonCodes, !codes.isEmpty {
            json[UPSTag.procedureStepDiscontinuationReasonCodeSequence] = ["vr": "SQ", "Value": codes.map(UPSEventJSON.codedEntry)]
        }
        return json
    }
}

// MARK: - UPSProgressReportEvent

/// Event generated when a workitem's progress is updated
///
/// Reference: PS3.4 Table CC.2.4-1 - UPS Progress Report (Event Type ID 3)
public struct UPSProgressReportEvent: UPSEvent, Sendable, Equatable {
    public let eventType: UPSEventType = .progressReport
    public let workitemUID: String
    public let transactionUID: String?
    public let timestamp: Date
    
    /// Progress information
    public let progressInformation: ProgressInformation
    
    /// Creates a progress report event
    public init(
        workitemUID: String,
        transactionUID: String? = nil,
        timestamp: Date = Date(),
        progressInformation: ProgressInformation
    ) {
        self.workitemUID = workitemUID
        self.transactionUID = transactionUID
        self.timestamp = timestamp
        self.progressInformation = progressInformation
    }
    
    /// The UPS Progress Report of PS3.4 Table CC.2.4-1 (Event Type ID 3): the Procedure Step
    /// Progress Information Sequence (0074,1002) with Progress, Progress Description and the
    /// Communications URI Sequence (Contact URI is Type 1 within it).
    public func toDICOMJSON() -> [String: Any] {
        var item: [String: Any] = [:]
        if let percentage = progressInformation.progressPercentage {
            item[UPSTag.procedureStepProgress] = ["vr": "DS", "Value": ["\(percentage)"]]
        }
        if let description = progressInformation.progressDescription {
            item[UPSTag.procedureStepProgressDescription] = ["vr": "ST", "Value": [description]]
        }
        if let contactURI = progressInformation.contactURI {
            var contact: [String: Any] = [UPSTag.contactURI: ["vr": "UR", "Value": [contactURI]]]
            if let contactName = progressInformation.contactDisplayName {
                contact[UPSTag.contactDisplayName] = ["vr": "LO", "Value": [contactName]]
            }
            item[UPSTag.procedureStepCommunicationsURISequence] = ["vr": "SQ", "Value": [contact]]
        }
        return [
            eventTypeIDTag: eventType.eventTypeIDAttribute,
            UPSTag.procedureStepProgressInformationSequence: ["vr": "SQ", "Value": [item]]
        ]
    }
}

// MARK: - UPSCancelRequestedEvent

/// Event generated when cancellation is requested for a workitem
///
/// Reference: PS3.4 Table CC.2.4-1 - UPS Cancel Requested (Event Type ID 2)
public struct UPSCancelRequestedEvent: UPSEvent, Sendable, Equatable {
    public let eventType: UPSEventType = .cancelRequested
    public let workitemUID: String
    public let transactionUID: String?
    public let timestamp: Date
    
    /// Reason for cancellation
    public let reason: String?
    
    /// Contact display name (who requested cancellation)
    public let contactDisplayName: String?
    
    /// Contact URI
    public let contactURI: String?
    
    /// Discontinuation reason codes
    public let discontinuationReasonCodes: [CodedEntry]?
    
    /// Creates a cancel requested event
    public init(
        workitemUID: String,
        transactionUID: String? = nil,
        timestamp: Date = Date(),
        reason: String? = nil,
        contactDisplayName: String? = nil,
        contactURI: String? = nil,
        discontinuationReasonCodes: [CodedEntry]? = nil
    ) {
        self.workitemUID = workitemUID
        self.transactionUID = transactionUID
        self.timestamp = timestamp
        self.reason = reason
        self.contactDisplayName = contactDisplayName
        self.contactURI = contactURI
        self.discontinuationReasonCodes = discontinuationReasonCodes
    }
    
    /// The UPS Cancel Requested report of PS3.4 Table CC.2.4-1 (Event Type ID 2). Requesting AE
    /// (0074,1236) is Type 1 and is added by the origin server that knows the requester.
    public func toDICOMJSON() -> [String: Any] {
        var json: [String: Any] = [eventTypeIDTag: eventType.eventTypeIDAttribute]
        if let reason = reason {
            json[UPSTag.reasonForCancellation] = ["vr": "LT", "Value": [reason]]
        }
        if let codes = discontinuationReasonCodes, !codes.isEmpty {
            json[UPSTag.procedureStepDiscontinuationReasonCodeSequence] = ["vr": "SQ", "Value": codes.map(UPSEventJSON.codedEntry)]
        }
        if let contactName = contactDisplayName {
            json[UPSTag.contactDisplayName] = ["vr": "LO", "Value": [contactName]]
        }
        if let contactURI = contactURI {
            json[UPSTag.contactURI] = ["vr": "UR", "Value": [contactURI]]
        }
        return json
    }
}

// MARK: - UPSAssignedEvent

/// Event generated when a workitem is assigned to a performer
///
/// Reference: PS3.4 Table CC.2.4-1 - UPS Assigned (Event Type ID 5)
public struct UPSAssignedEvent: UPSEvent, Sendable, Equatable {
    public let eventType: UPSEventType = .assigned
    public let workitemUID: String
    public let transactionUID: String?
    public let timestamp: Date
    
    /// Assigned performer
    public let performer: HumanPerformer
    
    /// Creates an assigned event
    public init(
        workitemUID: String,
        transactionUID: String? = nil,
        timestamp: Date = Date(),
        performer: HumanPerformer
    ) {
        self.workitemUID = workitemUID
        self.transactionUID = transactionUID
        self.timestamp = timestamp
        self.performer = performer
    }
    
    /// The UPS Assigned report of PS3.4 Table CC.2.4-1 (Event Type ID 5): Human Performer Code
    /// Sequence (0040,4009) and Human Performer's Organization (0040,4036), each required if
    /// populated in the UPS Instance. The Scheduled Station Name Code Sequence is not modelled.
    public func toDICOMJSON() -> [String: Any] {
        var json: [String: Any] = [eventTypeIDTag: eventType.eventTypeIDAttribute]
        if let code = performer.performerCode {
            json[UPSTag.humanPerformerCodeSequence] = ["vr": "SQ", "Value": [UPSEventJSON.codedEntry(code)]]
        }
        if let org = performer.performerOrganization {
            json[UPSTag.humanPerformerOrganization] = ["vr": "LO", "Value": [org]]
        }
        return json
    }
}

// MARK: - UPSCompletedEvent

/// Event generated when a workitem is completed
///
/// Not a PS3.4 event: a completion is a UPS State Report (Event Type ID 1) with state COMPLETED
public struct UPSCompletedEvent: UPSEvent, Sendable, Equatable {
    public let eventType: UPSEventType = .completed
    public let workitemUID: String
    public let transactionUID: String?
    public let timestamp: Date
    
    /// Completion reason or notes
    public let completionNotes: String?
    
    /// Creates a completed event
    public init(
        workitemUID: String,
        transactionUID: String? = nil,
        timestamp: Date = Date(),
        completionNotes: String? = nil
    ) {
        self.workitemUID = workitemUID
        self.transactionUID = transactionUID
        self.timestamp = timestamp
        self.completionNotes = completionNotes
    }
    
    /// Serialised as a UPS State Report (Event Type ID 1) with state COMPLETED; the completion
    /// notes have no attribute in PS3.4 Table CC.2.4-1 and are not sent.
    public func toDICOMJSON() -> [String: Any] {
        return UPSStateReportEvent(workitemUID: workitemUID, timestamp: timestamp,
                                   previousState: .inProgress, newState: .completed).toDICOMJSON()
    }
}

// MARK: - UPSCanceledEvent

/// Event generated when a workitem is canceled
///
/// Not a PS3.4 event: a cancellation is a UPS State Report (Event Type ID 1) with state CANCELED
public struct UPSCanceledEvent: UPSEvent, Sendable, Equatable {
    public let eventType: UPSEventType = .canceled
    public let workitemUID: String
    public let transactionUID: String?
    public let timestamp: Date
    
    /// Reason for cancellation
    public let reason: String?
    
    /// Discontinuation reason codes
    public let discontinuationReasonCodes: [CodedEntry]?
    
    /// Creates a canceled event
    public init(
        workitemUID: String,
        transactionUID: String? = nil,
        timestamp: Date = Date(),
        reason: String? = nil,
        discontinuationReasonCodes: [CodedEntry]? = nil
    ) {
        self.workitemUID = workitemUID
        self.transactionUID = transactionUID
        self.timestamp = timestamp
        self.reason = reason
        self.discontinuationReasonCodes = discontinuationReasonCodes
    }
    
    /// Serialised as a UPS State Report (Event Type ID 1) with state CANCELED and the optional
    /// Reason For Cancellation and Discontinuation Reason Code Sequence.
    public func toDICOMJSON() -> [String: Any] {
        return UPSStateReportEvent(workitemUID: workitemUID, timestamp: timestamp,
                                   previousState: .inProgress, newState: .canceled, reason: reason,
                                   discontinuationReasonCodes: discontinuationReasonCodes).toDICOMJSON()
    }
}

// MARK: - Type-Erased Event Container

/// Type-erased container for UPS events
public struct AnyUPSEvent: Sendable {
    private let _eventType: UPSEventType
    private let _workitemUID: String
    private let _transactionUID: String?
    private let _timestamp: Date
    private let _toDICOMJSON: @Sendable () -> [String: Any]
    
    public var eventType: UPSEventType { _eventType }
    public var workitemUID: String { _workitemUID }
    public var transactionUID: String? { _transactionUID }
    public var timestamp: Date { _timestamp }
    
    public init<E: UPSEvent>(_ event: E) {
        self._eventType = event.eventType
        self._workitemUID = event.workitemUID
        self._transactionUID = event.transactionUID
        self._timestamp = event.timestamp
        self._toDICOMJSON = { event.toDICOMJSON() }
    }
    
    public func toDICOMJSON() -> [String: Any] {
        return _toDICOMJSON()
    }
}


// MARK: - Shared JSON helpers

enum UPSEventJSON {
    /// A Code Sequence item (PS3.3 Table 8-1a Basic Code Sequence Macro)
    static func codedEntry(_ entry: CodedEntry) -> [String: Any] {
        var item: [String: Any] = [
            UPSTag.codeValue: ["vr": "SH", "Value": [entry.codeValue]],
            UPSTag.codingSchemeDesignator: ["vr": "SH", "Value": [entry.codingSchemeDesignator]],
            UPSTag.codeMeaning: ["vr": "LO", "Value": [entry.codeMeaning]]
        ]
        if let version = entry.codingSchemeVersion {
            item[UPSTag.codingSchemeVersion] = ["vr": "SH", "Value": [version]]
        }
        return item
    }
}
