import Foundation
// NEMA-verified: 2026a, checked 2026-09-28 — A-ABORT layout and source/reason semantics compared with PS3.8 2026a Table 9-26 (service-user source sends reason 00H)

/// A-ABORT PDU
///
/// Used to abnormally terminate an association.
///
/// Reference: PS3.8 Section 9.3.8
public struct AbortPDU: PDU, Sendable, Hashable {
    public let pduType: PDUType = .abort
    
    /// Source of the abort
    public let source: AbortSource
    
    /// Reason for the abort (only valid when source is service provider)
    ///
    /// When source is service user (0), reason should be 0.
    /// When source is service provider (2), reason indicates the cause.
    public let reason: UInt8
    
    /// Creates an A-ABORT PDU
    ///
    /// - Parameters:
    ///   - source: The source of the abort
    ///   - reason: The reason code (only meaningful when source is service provider)
    public init(source: AbortSource, reason: UInt8 = 0) {
        self.source = source
        self.reason = reason
    }
    
    /// Creates an A-ABORT PDU with a typed reason
    ///
    /// - Parameters:
    ///   - source: The source of the abort
    ///   - reason: The typed reason for abort
    public init(source: AbortSource, reason: AbortReason) {
        self.source = source
        self.reason = reason.rawValue
    }
    
    /// Encodes the PDU for network transmission
    ///
    /// Reference: PS3.8 Section 9.3.8
    public func encode() throws -> Data {
        var data = Data()
        
        // PDU Type (1 byte)
        data.append(pduType.rawValue)
        
        // Reserved (1 byte)
        data.append(0x00)
        
        // PDU Length (4 bytes, big endian) - always 4 for A-ABORT
        let pduLength = UInt32(4)
        data.append(contentsOf: withUnsafeBytes(of: pduLength.bigEndian) { Array($0) })
        
        // Reserved (2 bytes)
        data.append(contentsOf: [0x00, 0x00])
        
        // Source (1 byte)
        data.append(source.rawValue)
        
        // Reason/Diag (1 byte)
        // PS3.8 Table 9-26: for a service-user abort (source 0) this field is
        // not significant and "shall be sent with a value 00H".
        data.append(source == .serviceUser ? 0 : reason)
        
        return data
    }
    
    /// Human-readable reason description
    public var reasonDescription: String {
        guard source == .serviceProvider else {
            return "Not specified"
        }
        
        if let abortReason = AbortReason(rawValue: reason) {
            return abortReason.description
        } else {
            return "Unknown reason (\(reason))"
        }
    }
}

// MARK: - CustomStringConvertible
extension AbortPDU: CustomStringConvertible {
    public var description: String {
        """
        A-ABORT:
          Source: \(source)
          Reason: \(reasonDescription)
        """
    }
}
