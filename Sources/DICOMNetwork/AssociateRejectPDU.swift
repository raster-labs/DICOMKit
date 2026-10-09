import Foundation
// NEMA-verified: 2026a, checked 2026-09-28 — A-ASSOCIATE-RJ layout and the 12 result/source/reason texts text-diffed against PS3.8 2026a Table 9-21 (Scripts/diff_network.py): all match

/// A-ASSOCIATE-RJ PDU (Association Reject)
///
/// Used by the acceptor (SCP) to indicate rejection of an association request.
///
/// Reference: PS3.8 Section 9.3.4
public struct AssociateRejectPDU: PDU, Sendable, Hashable {
    public let pduType: PDUType = .associateReject
    
    /// Rejection result (permanent or transient)
    public let result: AssociateRejectResult
    
    /// Source of the rejection
    public let source: AssociateRejectSource
    
    /// Reason for rejection
    ///
    /// Interpretation depends on source:
    /// - Service User: 1=no-reason, 2=application-context-name-not-supported, 3=calling-AE-title-not-recognized, 7=called-AE-title-not-recognized
    /// - Service Provider (ACSE): 1=no-reason, 2=protocol-version-not-supported
    /// - Service Provider (Presentation): 1=temporary-congestion, 2=local-limit-exceeded
    public let reason: UInt8
    
    /// Creates an A-ASSOCIATE-RJ PDU
    ///
    /// - Parameters:
    ///   - result: The rejection result
    ///   - source: The source of the rejection
    ///   - reason: The reason code for rejection
    public init(result: AssociateRejectResult, source: AssociateRejectSource, reason: UInt8) {
        self.result = result
        self.source = source
        self.reason = reason
    }
    
    /// Encodes the PDU for network transmission
    ///
    /// Reference: PS3.8 Section 9.3.4
    public func encode() throws -> Data {
        var data = Data()
        
        // PDU Type (1 byte)
        data.append(pduType.rawValue)
        
        // Reserved (1 byte)
        data.append(0x00)
        
        // PDU Length (4 bytes, big endian) - always 4 for A-ASSOCIATE-RJ
        let pduLength = UInt32(4)
        data.append(contentsOf: withUnsafeBytes(of: pduLength.bigEndian) { Array($0) })
        
        // Reserved (1 byte)
        data.append(0x00)
        
        // Result (1 byte)
        data.append(result.rawValue)
        
        // Source (1 byte)
        data.append(source.rawValue)
        
        // Reason/Diag (1 byte)
        data.append(reason)
        
        return data
    }
    
    /// Human-readable reason description
    public var reasonDescription: String {
        switch source {
        case .serviceUser:
            switch reason {
            case 1: return "No reason given"
            case 2: return "Application context name not supported"
            case 3: return "Calling AE title not recognized"
            case 7: return "Called AE title not recognized"
            default: return "Unknown reason (\(reason))"
            }
        case .serviceProviderACSE:
            switch reason {
            case 1: return "No reason given"
            case 2: return "Protocol version not supported"
            default: return "Unknown reason (\(reason))"
            }
        case .serviceProviderPresentation:
            switch reason {
            case 1: return "Temporary congestion"
            case 2: return "Local limit exceeded"
            default: return "Unknown reason (\(reason))"
            }
        }
    }
}

// MARK: - CustomStringConvertible
extension AssociateRejectPDU: CustomStringConvertible {
    public var description: String {
        """
        A-ASSOCIATE-RJ:
          Result: \(result)
          Source: \(source)
          Reason: \(reasonDescription)
        """
    }
}
