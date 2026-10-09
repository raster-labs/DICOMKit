import Foundation
// NEMA-verified: 2026a, checked 2026-09-28 — A-RELEASE-RQ/RP layout compared with PS3.8 2026a Tables 9-24 and 9-25 (type, reserved, fixed length 4, 4 reserved bytes): match

/// A-RELEASE-RQ PDU (Release Request)
///
/// Used to initiate graceful release of an association.
///
/// Reference: PS3.8 Section 9.3.6
public struct ReleaseRequestPDU: PDU, Sendable, Hashable {
    public let pduType: PDUType = .releaseRequest
    
    /// Creates an A-RELEASE-RQ PDU
    public init() {}
    
    /// Encodes the PDU for network transmission
    ///
    /// Reference: PS3.8 Section 9.3.6
    public func encode() throws -> Data {
        var data = Data()
        
        // PDU Type (1 byte)
        data.append(pduType.rawValue)
        
        // Reserved (1 byte)
        data.append(0x00)
        
        // PDU Length (4 bytes, big endian) - always 4 for A-RELEASE-RQ
        let pduLength = UInt32(4)
        data.append(contentsOf: withUnsafeBytes(of: pduLength.bigEndian) { Array($0) })
        
        // Reserved (4 bytes)
        data.append(contentsOf: [0x00, 0x00, 0x00, 0x00])
        
        return data
    }
}

// MARK: - CustomStringConvertible
extension ReleaseRequestPDU: CustomStringConvertible {
    public var description: String {
        "A-RELEASE-RQ"
    }
}

/// A-RELEASE-RP PDU (Release Response)
///
/// Used to confirm graceful release of an association.
///
/// Reference: PS3.8 Section 9.3.7
public struct ReleaseResponsePDU: PDU, Sendable, Hashable {
    public let pduType: PDUType = .releaseResponse
    
    /// Creates an A-RELEASE-RP PDU
    public init() {}
    
    /// Encodes the PDU for network transmission
    ///
    /// Reference: PS3.8 Section 9.3.7
    public func encode() throws -> Data {
        var data = Data()
        
        // PDU Type (1 byte)
        data.append(pduType.rawValue)
        
        // Reserved (1 byte)
        data.append(0x00)
        
        // PDU Length (4 bytes, big endian) - always 4 for A-RELEASE-RP
        let pduLength = UInt32(4)
        data.append(contentsOf: withUnsafeBytes(of: pduLength.bigEndian) { Array($0) })
        
        // Reserved (4 bytes)
        data.append(contentsOf: [0x00, 0x00, 0x00, 0x00])
        
        return data
    }
}

// MARK: - CustomStringConvertible
extension ReleaseResponsePDU: CustomStringConvertible {
    public var description: String {
        "A-RELEASE-RP"
    }
}
