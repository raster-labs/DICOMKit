// NEMA-verified: 2026a, checked 2026-09-28 — the 7 PDU-type bytes text-diffed against PS3.8 2026a Tables 9-11, 9-17, 9-21, 9-22, 9-24, 9-25, 9-26 (Scripts/diff_network.py): 7 of 7 match
/// Protocol Data Unit (PDU) Types
///
/// Defines the types of PDUs used in DICOM Upper Layer Protocol communication.
///
/// Reference: DICOM PS3.8 Section 9.3 - Protocol Data Units
public enum PDUType: UInt8, Sendable, Hashable, CaseIterable {
    /// A-ASSOCIATE-RQ PDU
    ///
    /// Used by the requestor to initiate an association with an acceptor.
    /// Reference: PS3.8 Section 9.3.2
    case associateRequest = 0x01
    
    /// A-ASSOCIATE-AC PDU
    ///
    /// Used by the acceptor to indicate acceptance of an association request.
    /// Reference: PS3.8 Section 9.3.3
    case associateAccept = 0x02
    
    /// A-ASSOCIATE-RJ PDU
    ///
    /// Used by the acceptor to indicate rejection of an association request.
    /// Reference: PS3.8 Section 9.3.4
    case associateReject = 0x03
    
    /// P-DATA-TF PDU
    ///
    /// Used to transfer DICOM message data after association is established.
    /// Reference: PS3.8 Section 9.3.5
    case dataTransfer = 0x04
    
    /// A-RELEASE-RQ PDU
    ///
    /// Used to initiate graceful release of an association.
    /// Reference: PS3.8 Section 9.3.6
    case releaseRequest = 0x05
    
    /// A-RELEASE-RP PDU
    ///
    /// Used to confirm graceful release of an association.
    /// Reference: PS3.8 Section 9.3.7
    case releaseResponse = 0x06
    
    /// A-ABORT PDU
    ///
    /// Used to abnormally terminate an association.
    /// Reference: PS3.8 Section 9.3.8
    case abort = 0x07
}

// MARK: - CustomStringConvertible
extension PDUType: CustomStringConvertible {
    public var description: String {
        switch self {
        case .associateRequest:
            return "A-ASSOCIATE-RQ"
        case .associateAccept:
            return "A-ASSOCIATE-AC"
        case .associateReject:
            return "A-ASSOCIATE-RJ"
        case .dataTransfer:
            return "P-DATA-TF"
        case .releaseRequest:
            return "A-RELEASE-RQ"
        case .releaseResponse:
            return "A-RELEASE-RP"
        case .abort:
            return "A-ABORT"
        }
    }
}
