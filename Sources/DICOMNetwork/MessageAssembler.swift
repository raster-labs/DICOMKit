import Foundation
import DICOMCore
// NEMA-verified: 2026a, checked 2026-09-28 — fragment size derived from the PDU-length definition of PS3.8 2026a §9.3.1 / Table 9-23 (maximum length − 6 bytes per PDV) and the Annex E.2 control header

/// Assembles DIMSE messages from PDV fragments
///
/// Handles the assembly of command and data set fragments from multiple
/// P-DATA-TF PDUs into complete DIMSE messages.
///
/// Reference: PS3.8 Section 9.3.5 - P-DATA-TF PDU Structure
public final class MessageAssembler: @unchecked Sendable {
    
    /// Buffer for accumulating command fragments
    private var commandBuffer: Data = Data()
    
    /// Buffer for accumulating data set fragments
    private var dataSetBuffer: Data = Data()
    
    /// The presentation context ID for the current message
    private var currentContextID: UInt8?
    
    /// Whether the command is complete
    private var commandComplete = false
    
    /// Whether the data set is complete (or not expected)
    private var dataSetComplete = false
    
    /// Lock for thread-safe operations
    private let lock = NSLock()
    
    /// Creates a new message assembler
    public init() {}
    
    /// Resets the assembler state
    public func reset() {
        lock.lock()
        defer { lock.unlock() }
        
        commandBuffer = Data()
        dataSetBuffer = Data()
        currentContextID = nil
        commandComplete = false
        dataSetComplete = false
    }
    
    /// Adds a PDV to the assembler
    ///
    /// - Parameter pdv: The Presentation Data Value to add
    /// - Returns: An assembled message if complete, nil otherwise
    /// - Throws: `DICOMNetworkError.decodingFailed` if PDV is invalid
    public func addPDV(_ pdv: PresentationDataValue) throws -> AssembledMessage? {
        lock.lock()
        defer { lock.unlock() }
        
        // Check context ID consistency
        if let ctxID = currentContextID {
            guard pdv.presentationContextID == ctxID else {
                throw DICOMNetworkError.decodingFailed(
                    "Context ID mismatch: expected \(ctxID), got \(pdv.presentationContextID)"
                )
            }
        } else {
            currentContextID = pdv.presentationContextID
        }
        
        if pdv.isCommand {
            commandBuffer.append(pdv.data)
            if pdv.isLastFragment {
                commandComplete = true
            }
        } else {
            dataSetBuffer.append(pdv.data)
            if pdv.isLastFragment {
                dataSetComplete = true
            }
        }
        
        // Check if message is complete
        if commandComplete {
            // Decode command to check if data set is expected
            let commandSet = try CommandSet.decode(from: commandBuffer)
            
            if commandSet.hasDataSet {
                // Need data set
                if dataSetComplete {
                    return makeAssembledMessage(commandSet: commandSet)
                }
            } else {
                // No data set expected
                dataSetComplete = true
                return makeAssembledMessage(commandSet: commandSet)
            }
        }
        
        return nil
    }
    
    /// Adds multiple PDVs from a P-DATA-TF PDU
    ///
    /// - Parameter dataTransferPDU: The P-DATA-TF PDU
    /// - Returns: An assembled message if complete, nil otherwise
    /// - Throws: `DICOMNetworkError.decodingFailed` if PDV is invalid
    public func addPDVs(from dataTransferPDU: DataTransferPDU) throws -> AssembledMessage? {
        var result: AssembledMessage? = nil
        
        for pdv in dataTransferPDU.presentationDataValues {
            if let message = try addPDV(pdv) {
                result = message
            }
        }
        
        return result
    }
    
    /// Creates the assembled message and resets state
    private func makeAssembledMessage(commandSet: CommandSet) -> AssembledMessage {
        let message = AssembledMessage(
            presentationContextID: currentContextID ?? 1,
            commandSet: commandSet,
            dataSet: dataSetBuffer.isEmpty ? nil : dataSetBuffer
        )
        
        // Reset for next message
        commandBuffer = Data()
        dataSetBuffer = Data()
        currentContextID = nil
        commandComplete = false
        dataSetComplete = false
        
        return message
    }
    
    /// Whether the assembler is currently processing a message
    public var isProcessing: Bool {
        lock.lock()
        defer { lock.unlock() }
        return !commandBuffer.isEmpty || !dataSetBuffer.isEmpty
    }
}

/// An assembled DIMSE message with command set and optional data set
public struct AssembledMessage: Sendable {
    /// The presentation context ID
    public let presentationContextID: UInt8
    
    /// The decoded command set
    public let commandSet: CommandSet
    
    /// The raw data set bytes (if present)
    public let dataSet: Data?
    
    /// Whether this message has a data set
    public var hasDataSet: Bool {
        dataSet != nil
    }
    
    /// The DIMSE command type
    public var command: DIMSECommand? {
        commandSet.command
    }
    
    /// Creates a C-ECHO request from this message
    public func asCEchoRequest() -> CEchoRequest? {
        guard commandSet.command == .cEchoRequest else { return nil }
        return CEchoRequest(commandSet: commandSet, presentationContextID: presentationContextID)
    }
    
    /// Creates a C-ECHO response from this message
    public func asCEchoResponse() -> CEchoResponse? {
        guard commandSet.command == .cEchoResponse else { return nil }
        return CEchoResponse(commandSet: commandSet, presentationContextID: presentationContextID)
    }
    
    /// Creates a C-STORE request from this message
    public func asCStoreRequest() -> CStoreRequest? {
        guard commandSet.command == .cStoreRequest else { return nil }
        return CStoreRequest(commandSet: commandSet, presentationContextID: presentationContextID)
    }
    
    /// Creates a C-STORE response from this message
    public func asCStoreResponse() -> CStoreResponse? {
        guard commandSet.command == .cStoreResponse else { return nil }
        return CStoreResponse(commandSet: commandSet, presentationContextID: presentationContextID)
    }
    
    /// Creates a C-FIND request from this message
    public func asCFindRequest() -> CFindRequest? {
        guard commandSet.command == .cFindRequest else { return nil }
        return CFindRequest(commandSet: commandSet, presentationContextID: presentationContextID)
    }
    
    /// Creates a C-FIND response from this message
    public func asCFindResponse() -> CFindResponse? {
        guard commandSet.command == .cFindResponse else { return nil }
        return CFindResponse(commandSet: commandSet, presentationContextID: presentationContextID)
    }
    
    /// Creates a C-MOVE request from this message
    public func asCMoveRequest() -> CMoveRequest? {
        guard commandSet.command == .cMoveRequest else { return nil }
        return CMoveRequest(commandSet: commandSet, presentationContextID: presentationContextID)
    }
    
    /// Creates a C-MOVE response from this message
    public func asCMoveResponse() -> CMoveResponse? {
        guard commandSet.command == .cMoveResponse else { return nil }
        return CMoveResponse(commandSet: commandSet, presentationContextID: presentationContextID)
    }
    
    /// Creates a C-GET request from this message
    public func asCGetRequest() -> CGetRequest? {
        guard commandSet.command == .cGetRequest else { return nil }
        return CGetRequest(commandSet: commandSet, presentationContextID: presentationContextID)
    }
    
    /// Creates a C-GET response from this message
    public func asCGetResponse() -> CGetResponse? {
        guard commandSet.command == .cGetResponse else { return nil }
        return CGetResponse(commandSet: commandSet, presentationContextID: presentationContextID)
    }
    
    /// Creates a C-CANCEL request from this message
    public func asCCancelRequest() -> CCancelRequest? {
        guard commandSet.command == .cCancelRequest else { return nil }
        return CCancelRequest(commandSet: commandSet, presentationContextID: presentationContextID)
    }
}

// MARK: - Message Fragmentation

/// Fragments a DIMSE message into PDVs suitable for transmission
///
/// Large messages may need to be split across multiple P-DATA-TF PDUs.
///
/// Reference: PS3.8 Section 9.3.5
public struct MessageFragmenter: Sendable {
    
    /// Maximum PDV size (payload only, excluding 6-byte PDV header)
    public let maxPDVDataSize: UInt32
    
    /// Overhead of one PDV item inside a P-DATA-TF PDU: 4 (item length) +
    /// 1 (presentation context ID) + 1 (message control header)
    ///
    /// Reference: PS3.8 Table 9-23
    static let pdvItemOverhead: UInt32 = 6
    
    /// Creates a message fragmenter
    ///
    /// - Parameter maxPDUSize: The peer's Maximum Length Received (PS3.8
    ///   Annex D.1); 0 means no maximum is specified and `defaultMaxPDUSize`
    ///   is used as the practical fragment size
    public init(maxPDUSize: UInt32) {
        // PS3.8 Table 9-22: the PDU-length field counts the variable field
        // only, i.e. the PDV item(s) that follow the 6-byte PDU header. One
        // PDV per PDU therefore carries maxPDUSize - 6 bytes of data.
        // Annex D.1: 0 = "no maximum length is specified".
        let effective = maxPDUSize == 0 ? defaultMaxPDUSize : maxPDUSize
        if effective > Self.pdvItemOverhead {
            self.maxPDVDataSize = effective - Self.pdvItemOverhead
        } else {
            self.maxPDVDataSize = defaultMaxPDUSize - Self.pdvItemOverhead
        }
    }
    
    /// Fragments a command set into PDVs
    ///
    /// - Parameters:
    ///   - commandSet: The command set to fragment
    ///   - presentationContextID: The presentation context ID
    /// - Returns: Array of PDVs containing the fragmented command
    public func fragmentCommand(
        _ commandSet: CommandSet,
        presentationContextID: UInt8
    ) -> [PresentationDataValue] {
        let data = commandSet.encode()
        return fragment(data, presentationContextID: presentationContextID, isCommand: true)
    }
    
    /// Fragments a data set into PDVs
    ///
    /// - Parameters:
    ///   - dataSet: The data set bytes to fragment
    ///   - presentationContextID: The presentation context ID
    /// - Returns: Array of PDVs containing the fragmented data set
    public func fragmentDataSet(
        _ dataSet: Data,
        presentationContextID: UInt8
    ) -> [PresentationDataValue] {
        return fragment(dataSet, presentationContextID: presentationContextID, isCommand: false)
    }
    
    /// Fragments data into PDVs
    private func fragment(
        _ data: Data,
        presentationContextID: UInt8,
        isCommand: Bool
    ) -> [PresentationDataValue] {
        var pdvs: [PresentationDataValue] = []
        var offset = 0
        
        while offset < data.count {
            let remaining = data.count - offset
            let chunkSize = min(remaining, Int(maxPDVDataSize))
            let isLast = (offset + chunkSize) >= data.count
            
            let chunk = data.subdata(in: offset..<(offset + chunkSize))
            
            let pdv = PresentationDataValue(
                presentationContextID: presentationContextID,
                isCommand: isCommand,
                isLastFragment: isLast,
                data: chunk
            )
            
            pdvs.append(pdv)
            offset += chunkSize
        }
        
        return pdvs
    }
    
    /// Creates P-DATA-TF PDUs from PDVs, respecting the maximum PDU size
    ///
    /// - Parameter pdvs: The PDVs to package
    /// - Returns: Array of P-DATA-TF PDUs
    public func createDataTransferPDUs(from pdvs: [PresentationDataValue]) -> [DataTransferPDU] {
        // For simplicity, put one PDV per PDU
        // A more sophisticated implementation could pack multiple small PDVs
        return pdvs.map { DataTransferPDU(pdv: $0) }
    }
    
    /// Fragments a complete DIMSE message into P-DATA-TF PDUs
    ///
    /// - Parameters:
    ///   - commandSet: The command set
    ///   - dataSet: The optional data set
    ///   - presentationContextID: The presentation context ID
    /// - Returns: Array of P-DATA-TF PDUs ready for transmission
    public func fragmentMessage(
        commandSet: CommandSet,
        dataSet: Data?,
        presentationContextID: UInt8
    ) -> [DataTransferPDU] {
        var pdvs = fragmentCommand(commandSet, presentationContextID: presentationContextID)
        
        if let ds = dataSet {
            pdvs.append(contentsOf: fragmentDataSet(ds, presentationContextID: presentationContextID))
        }
        
        return createDataTransferPDUs(from: pdvs)
    }
}
