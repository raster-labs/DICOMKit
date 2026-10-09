import Foundation
// NEMA-verified: 2026a, checked 2026-09-28 — P-DATA-TF and PDV layout compared with PS3.8 2026a Tables 9-22, 9-23 and the Annex E.2 message control header (bit 0 command, bit 1 last fragment): match

/// P-DATA-TF PDU (Data Transfer)
///
/// Used to transfer DICOM message data after association is established.
/// Contains one or more Presentation Data Values (PDVs).
///
/// Reference: PS3.8 Section 9.3.5
public struct DataTransferPDU: PDU, Sendable, Hashable {
    public let pduType: PDUType = .dataTransfer
    
    /// The Presentation Data Values contained in this PDU
    public let presentationDataValues: [PresentationDataValue]
    
    /// Creates a P-DATA-TF PDU with the given PDVs
    ///
    /// - Parameter presentationDataValues: One or more PDVs to include
    public init(presentationDataValues: [PresentationDataValue]) {
        self.presentationDataValues = presentationDataValues
    }
    
    /// Creates a P-DATA-TF PDU with a single PDV
    ///
    /// - Parameter pdv: The single PDV to include
    public init(pdv: PresentationDataValue) {
        self.presentationDataValues = [pdv]
    }
    
    /// Encodes the PDU for network transmission
    ///
    /// Reference: PS3.8 Section 9.3.5
    public func encode() throws -> Data {
        var data = Data()
        
        // Encode all PDVs first to calculate total length
        var pdvData = Data()
        for pdv in presentationDataValues {
            pdvData.append(pdv.encode())
        }
        
        // PDU Type (1 byte)
        data.append(pduType.rawValue)
        
        // Reserved (1 byte)
        data.append(0x00)
        
        // PDU Length (4 bytes, big endian)
        let pduLength = UInt32(pdvData.count)
        data.append(contentsOf: withUnsafeBytes(of: pduLength.bigEndian) { Array($0) })
        
        // PDV Items
        data.append(pdvData)
        
        return data
    }
    
    /// Total data length including all PDVs
    public var totalDataLength: Int {
        presentationDataValues.reduce(0) { $0 + $1.data.count }
    }
}

// MARK: - CustomStringConvertible
extension DataTransferPDU: CustomStringConvertible {
    public var description: String {
        "P-DATA-TF: \(presentationDataValues.count) PDV(s), \(totalDataLength) bytes"
    }
}

/// Presentation Data Value (PDV)
///
/// Carries a fragment of a DICOM message (command or data set).
///
/// Reference: PS3.8 Section 9.3.5.1
public struct PresentationDataValue: Sendable, Hashable {
    /// Presentation Context ID that this PDV belongs to
    public let presentationContextID: UInt8
    
    /// Whether this PDV contains a command (true) or data set (false)
    public let isCommand: Bool
    
    /// Whether this is the last fragment of the message
    public let isLastFragment: Bool
    
    /// The actual data payload
    public let data: Data
    
    /// Creates a Presentation Data Value
    ///
    /// - Parameters:
    ///   - presentationContextID: The presentation context ID
    ///   - isCommand: True if this is a command, false if data set
    ///   - isLastFragment: True if this is the last fragment
    ///   - data: The data payload
    public init(
        presentationContextID: UInt8,
        isCommand: Bool,
        isLastFragment: Bool,
        data: Data
    ) {
        self.presentationContextID = presentationContextID
        self.isCommand = isCommand
        self.isLastFragment = isLastFragment
        self.data = data
    }
    
    /// The Message Control Header byte
    ///
    /// Bit 0: 0 = Data Set, 1 = Command
    /// Bit 1: 0 = Not Last, 1 = Last
    public var messageControlHeader: UInt8 {
        var header: UInt8 = 0
        if isCommand { header |= 0x01 }
        if isLastFragment { header |= 0x02 }
        return header
    }
    
    /// Encodes the PDV for inclusion in a P-DATA-TF PDU
    func encode() -> Data {
        var encoded = Data()
        
        // PDV Item Length (4 bytes, big endian)
        // Length includes Presentation Context ID (1) + Message Control Header (1) + data
        let itemLength = UInt32(2 + data.count)
        encoded.append(contentsOf: withUnsafeBytes(of: itemLength.bigEndian) { Array($0) })
        
        // Presentation Context ID (1 byte)
        encoded.append(presentationContextID)
        
        // Message Control Header (1 byte)
        encoded.append(messageControlHeader)
        
        // Data
        encoded.append(data)
        
        return encoded
    }
}

// MARK: - CustomStringConvertible
extension PresentationDataValue: CustomStringConvertible {
    public var description: String {
        let type = isCommand ? "Command" : "Data Set"
        let fragment = isLastFragment ? "Last" : "Fragment"
        return "PDV(context=\(presentationContextID), type=\(type), \(fragment), \(data.count) bytes)"
    }
}
