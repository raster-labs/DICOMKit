import Foundation
// NEMA-verified: 2026a, checked 2026-09-28 — the 23 Command Field values text-diffed against PS3.7 2026a Table E.1-1 (0000,0100) (Scripts/diff_network.py): 23 of 23 match

/// DIMSE Command Field values
///
/// Identifies the type of DIMSE operation in the Command Set.
///
/// Reference: PS3.7 Table E.1-1 - Command Fields
public enum DIMSECommand: UInt16, Sendable, Hashable {
    // MARK: - DIMSE-C Services
    
    /// C-STORE Request (0x0001)
    case cStoreRequest = 0x0001
    
    /// C-STORE Response (0x8001)
    case cStoreResponse = 0x8001
    
    /// C-GET Request (0x0010)
    case cGetRequest = 0x0010
    
    /// C-GET Response (0x8010)
    case cGetResponse = 0x8010
    
    /// C-FIND Request (0x0020)
    case cFindRequest = 0x0020
    
    /// C-FIND Response (0x8020)
    case cFindResponse = 0x8020
    
    /// C-MOVE Request (0x0021)
    case cMoveRequest = 0x0021
    
    /// C-MOVE Response (0x8021)
    case cMoveResponse = 0x8021
    
    /// C-ECHO Request (0x0030)
    case cEchoRequest = 0x0030
    
    /// C-ECHO Response (0x8030)
    case cEchoResponse = 0x8030
    
    // MARK: - DIMSE-N Services
    
    /// N-EVENT-REPORT Request (0x0100)
    case nEventReportRequest = 0x0100
    
    /// N-EVENT-REPORT Response (0x8100)
    case nEventReportResponse = 0x8100
    
    /// N-GET Request (0x0110)
    case nGetRequest = 0x0110
    
    /// N-GET Response (0x8110)
    case nGetResponse = 0x8110
    
    /// N-SET Request (0x0120)
    case nSetRequest = 0x0120
    
    /// N-SET Response (0x8120)
    case nSetResponse = 0x8120
    
    /// N-ACTION Request (0x0130)
    case nActionRequest = 0x0130
    
    /// N-ACTION Response (0x8130)
    case nActionResponse = 0x8130
    
    /// N-CREATE Request (0x0140)
    case nCreateRequest = 0x0140
    
    /// N-CREATE Response (0x8140)
    case nCreateResponse = 0x8140
    
    /// N-DELETE Request (0x0150)
    case nDeleteRequest = 0x0150
    
    /// N-DELETE Response (0x8150)
    case nDeleteResponse = 0x8150
    
    /// C-CANCEL Request (0x0FFF)
    case cCancelRequest = 0x0FFF
    
    /// Whether this is a request command
    public var isRequest: Bool {
        (rawValue & 0x8000) == 0
    }
    
    /// Whether this is a response command
    public var isResponse: Bool {
        (rawValue & 0x8000) != 0
    }
    
    /// The corresponding request command for a response
    public var requestCommand: DIMSECommand? {
        guard isResponse else { return self }
        guard let cmd = DIMSECommand(rawValue: rawValue & 0x7FFF) else { return nil }
        return cmd
    }
    
    /// The corresponding response command for a request
    public var responseCommand: DIMSECommand? {
        guard isRequest else { return self }
        if self == .cCancelRequest { return nil }
        guard let cmd = DIMSECommand(rawValue: rawValue | 0x8000) else { return nil }
        return cmd
    }
}

// MARK: - CustomStringConvertible
extension DIMSECommand: CustomStringConvertible {
    public var description: String {
        switch self {
        case .cStoreRequest: return "C-STORE-RQ"
        case .cStoreResponse: return "C-STORE-RSP"
        case .cGetRequest: return "C-GET-RQ"
        case .cGetResponse: return "C-GET-RSP"
        case .cFindRequest: return "C-FIND-RQ"
        case .cFindResponse: return "C-FIND-RSP"
        case .cMoveRequest: return "C-MOVE-RQ"
        case .cMoveResponse: return "C-MOVE-RSP"
        case .cEchoRequest: return "C-ECHO-RQ"
        case .cEchoResponse: return "C-ECHO-RSP"
        case .nEventReportRequest: return "N-EVENT-REPORT-RQ"
        case .nEventReportResponse: return "N-EVENT-REPORT-RSP"
        case .nGetRequest: return "N-GET-RQ"
        case .nGetResponse: return "N-GET-RSP"
        case .nSetRequest: return "N-SET-RQ"
        case .nSetResponse: return "N-SET-RSP"
        case .nActionRequest: return "N-ACTION-RQ"
        case .nActionResponse: return "N-ACTION-RSP"
        case .nCreateRequest: return "N-CREATE-RQ"
        case .nCreateResponse: return "N-CREATE-RSP"
        case .nDeleteRequest: return "N-DELETE-RQ"
        case .nDeleteResponse: return "N-DELETE-RSP"
        case .cCancelRequest: return "C-CANCEL-RQ"
        }
    }
}
