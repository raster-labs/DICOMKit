import Foundation
// NEMA-verified: 2026a, checked 2026-09-28 — decoder compared with PS3.8 2026a Tables 9-11..9-26 and PS3.7 Tables D.3-1..D.3-15 (item types 0x10-0x59; 0x53/0x57 skipped as §9.3.1 permits; 0x56 SOP Class Extended Negotiation decoded per Table D.3-11 (2026-10-01); Protocol-version preserved for the bit-0 test)

/// PDU Decoder for parsing DICOM network PDUs from binary data
///
/// Reference: PS3.8 Section 9 - Protocol Data Units
public enum PDUDecoder {

    /// Maximum accepted declared PDU length (128 MB)
    ///
    /// A peer-supplied PDU length drives buffer allocation in the network
    /// layer; without a ceiling, a hostile peer can declare a multi-gigabyte
    /// PDU and force an allocation DoS. P-DATA-TF PDUs are normally bounded by
    /// the negotiated Maximum Length; 128 MB is far above any legitimate PDU.
    public static let maximumPDULength: UInt32 = 128 * 1024 * 1024

    // MARK: - Helper Methods for Reading Big Endian Values
    
    private static func readUInt16BigEndian(from data: Data, at offset: Data.Index) -> UInt16 {
        return (UInt16(data[offset]) << 8) | UInt16(data[offset + 1])
    }
    
    private static func readUInt32BigEndian(from data: Data, at offset: Data.Index) -> UInt32 {
        return (UInt32(data[offset]) << 24) |
               (UInt32(data[offset + 1]) << 16) |
               (UInt32(data[offset + 2]) << 8) |
               UInt32(data[offset + 3])
    }
    
    /// Decodes a PDU from binary data
    ///
    /// - Parameter data: The raw PDU data
    /// - Returns: The decoded PDU
    /// - Throws: `DICOMNetworkError` if decoding fails
    public static func decode(from data: Data) throws -> any PDU {
        guard data.count >= 6 else {
            throw DICOMNetworkError.decodingFailed("PDU too short: need at least 6 bytes, got \(data.count)")
        }
        
        // Read PDU Type (1 byte)
        let pduTypeByte = data[data.startIndex]
        guard let pduType = PDUType(rawValue: pduTypeByte) else {
            throw DICOMNetworkError.decodingFailed("Unknown PDU type: 0x\(String(format: "%02X", pduTypeByte))")
        }
        
        // Skip reserved byte (1 byte)
        // Read PDU Length (4 bytes, big endian)
        let pduLength = readUInt32BigEndian(from: data, at: data.startIndex + 2)

        guard pduLength <= Self.maximumPDULength else {
            throw DICOMNetworkError.limitExceeded(
                "Declared PDU length \(pduLength) exceeds maximum (\(Self.maximumPDULength))")
        }

        let expectedTotalLength = 6 + Int(pduLength)
        guard data.count >= expectedTotalLength else {
            throw DICOMNetworkError.decodingFailed("PDU data too short: expected \(expectedTotalLength) bytes, got \(data.count)")
        }
        
        let variableField = Data(data[data.startIndex + 6 ..< data.startIndex + expectedTotalLength])
        
        switch pduType {
        case .associateRequest:
            return try decodeAssociateRequest(from: variableField)
        case .associateAccept:
            return try decodeAssociateAccept(from: variableField)
        case .associateReject:
            return try decodeAssociateReject(from: variableField)
        case .dataTransfer:
            return try decodeDataTransfer(from: variableField)
        case .releaseRequest:
            return ReleaseRequestPDU()
        case .releaseResponse:
            return ReleaseResponsePDU()
        case .abort:
            return try decodeAbort(from: variableField)
        }
    }
    
    /// Reads the PDU header to determine type and length without full parsing
    ///
    /// - Parameter data: At least 6 bytes of PDU header data
    /// - Returns: Tuple of (PDU type, PDU length)
    /// - Throws: `DICOMNetworkError` if header is invalid
    public static func readHeader(from data: Data) throws -> (type: PDUType, length: UInt32) {
        guard data.count >= 6 else {
            throw DICOMNetworkError.decodingFailed("PDU header too short: need 6 bytes, got \(data.count)")
        }
        
        let pduTypeByte = data[data.startIndex]
        guard let pduType = PDUType(rawValue: pduTypeByte) else {
            throw DICOMNetworkError.decodingFailed("Unknown PDU type: 0x\(String(format: "%02X", pduTypeByte))")
        }
        
        let pduLength = readUInt32BigEndian(from: data, at: data.startIndex + 2)

        guard pduLength <= Self.maximumPDULength else {
            throw DICOMNetworkError.limitExceeded(
                "Declared PDU length \(pduLength) exceeds maximum (\(Self.maximumPDULength))")
        }

        return (pduType, pduLength)
    }
    
    // MARK: - Private Decoding Methods
    
    private static func decodeAssociateRequest(from data: Data) throws -> AssociateRequestPDU {
        var offset = data.startIndex
        
        guard data.count >= 68 else {
            throw DICOMNetworkError.decodingFailed("A-ASSOCIATE-RQ too short")
        }
        
        // Protocol Version (2 bytes) - kept so the SCP can test bit 0 (PS3.8 Table 9-11)
        let protocolVersion = readUInt16BigEndian(from: data, at: offset)
        offset += 2
        
        // Reserved (2 bytes)
        offset += 2
        
        // Called AE Title (16 bytes)
        let calledAEData = Data(data[offset ..< offset + 16])
        guard let calledAETitle = AETitle.from(data: calledAEData) else {
            throw DICOMNetworkError.decodingFailed("Invalid Called AE Title")
        }
        offset += 16
        
        // Calling AE Title (16 bytes)
        let callingAEData = Data(data[offset ..< offset + 16])
        guard let callingAETitle = AETitle.from(data: callingAEData) else {
            throw DICOMNetworkError.decodingFailed("Invalid Calling AE Title")
        }
        offset += 16
        
        // Reserved (32 bytes)
        offset += 32
        
        // Parse variable items
        var applicationContextName = AssociateRequestPDU.dicomApplicationContextName
        var presentationContexts: [PresentationContext] = []
        var maxPDUSize: UInt32 = defaultMaxPDUSize
        var implementationClassUID = ""
        var implementationVersionName: String?
        var userIdentity: UserIdentity?
        var roleSelections: [SCPSCURoleSelection] = []
        var extendedNegotiations: [SOPClassExtendedNegotiation] = []
        
        while offset < data.endIndex {
            guard offset + 4 <= data.endIndex else { break }
            
            let itemType = data[offset]
            offset += 1
            offset += 1 // Reserved
            
            let itemLength = readUInt16BigEndian(from: data, at: offset)
            offset += 2
            
            guard offset + Int(itemLength) <= data.endIndex else { break }
            let itemData = Data(data[offset ..< offset + Int(itemLength)])
            offset += Int(itemLength)
            
            switch itemType {
            case 0x10: // Application Context
                applicationContextName = String(data: itemData, encoding: .ascii) ?? applicationContextName
                
            case 0x20: // Presentation Context (RQ)
                if let context = try? decodePresentationContextRQ(from: itemData) {
                    presentationContexts.append(context)
                }
                
            case 0x50: // User Information
                let userInfo = try decodeUserInformationFull(from: itemData)
                maxPDUSize = userInfo.maxPDUSize ?? maxPDUSize
                implementationClassUID = userInfo.implementationClassUID ?? implementationClassUID
                implementationVersionName = userInfo.implementationVersionName
                userIdentity = userInfo.userIdentity
                roleSelections = userInfo.roleSelections
                extendedNegotiations = userInfo.extendedNegotiations
                
            default:
                break // Unknown item type, skip
            }
        }
        
        return AssociateRequestPDU(
            protocolVersion: protocolVersion,
            calledAETitle: calledAETitle,
            callingAETitle: callingAETitle,
            presentationContexts: presentationContexts,
            maxPDUSize: maxPDUSize,
            implementationClassUID: implementationClassUID,
            implementationVersionName: implementationVersionName,
            userIdentity: userIdentity,
            applicationContextName: applicationContextName,
            roleSelections: roleSelections,
            extendedNegotiations: extendedNegotiations
        )
    }
    
    private static func decodePresentationContextRQ(from data: Data) throws -> PresentationContext {
        guard data.count >= 4 else {
            throw DICOMNetworkError.decodingFailed("Presentation Context item too short")
        }
        
        var offset = data.startIndex
        
        let contextID = data[offset]
        offset += 4 // ID + 3 reserved bytes
        
        var abstractSyntax = ""
        var transferSyntaxes: [String] = []
        
        while offset < data.endIndex {
            guard offset + 4 <= data.endIndex else { break }
            
            let subItemType = data[offset]
            offset += 2 // Type + Reserved
            
            let subItemLength = readUInt16BigEndian(from: data, at: offset)
            offset += 2
            
            guard offset + Int(subItemLength) <= data.endIndex else { break }
            let subItemData = Data(data[offset ..< offset + Int(subItemLength)])
            offset += Int(subItemLength)
            
            if subItemType == 0x30 { // Abstract Syntax
                abstractSyntax = String(data: subItemData, encoding: .ascii) ?? ""
            } else if subItemType == 0x40 { // Transfer Syntax
                if let ts = String(data: subItemData, encoding: .ascii) {
                    transferSyntaxes.append(ts)
                }
            }
        }
        
        return try PresentationContext(id: contextID, abstractSyntax: abstractSyntax, transferSyntaxes: transferSyntaxes)
    }
    
    /// User information result from decoding
    private struct UserInformationResult {
        var maxPDUSize: UInt32?
        var implementationClassUID: String?
        var implementationVersionName: String?
        var userIdentity: UserIdentity?
        var userIdentityServerResponse: UserIdentityServerResponse?
        var roleSelections: [SCPSCURoleSelection] = []
        var extendedNegotiations: [SOPClassExtendedNegotiation] = []
    }
    
    private static func decodeUserInformationFull(from data: Data) throws -> UserInformationResult {
        var offset = data.startIndex
        var result = UserInformationResult()
        
        while offset < data.endIndex {
            guard offset + 4 <= data.endIndex else { break }
            
            let subItemType = data[offset]
            offset += 2 // Type + Reserved
            
            let subItemLength = readUInt16BigEndian(from: data, at: offset)
            offset += 2
            
            guard offset + Int(subItemLength) <= data.endIndex else { break }
            let subItemData = Data(data[offset ..< offset + Int(subItemLength)])
            offset += Int(subItemLength)
            
            switch subItemType {
            case 0x51: // Maximum Length
                if subItemLength >= 4 {
                    result.maxPDUSize = readUInt32BigEndian(from: subItemData, at: subItemData.startIndex)
                }
            case 0x52: // Implementation Class UID
                result.implementationClassUID = String(data: subItemData, encoding: .ascii)
            case SCPSCURoleSelection.subItemType: // SCP/SCU Role Selection (PS3.7 D.3.3.4)
                if let role = try? SCPSCURoleSelection.decode(from: subItemData) {
                    result.roleSelections.append(role)
                }
            case SOPClassExtendedNegotiation.subItemType: // SOP Class Extended Negotiation (PS3.7 D.3.3.5)
                if let negotiation = try? SOPClassExtendedNegotiation.decode(from: subItemData) {
                    result.extendedNegotiations.append(negotiation)
                }
            case 0x55: // Implementation Version Name
                result.implementationVersionName = String(data: subItemData, encoding: .ascii)
            case 0x58: // User Identity (A-ASSOCIATE-RQ)
                result.userIdentity = try decodeUserIdentity(from: subItemData)
            case 0x59: // User Identity Server Response (A-ASSOCIATE-AC)
                result.userIdentityServerResponse = try decodeUserIdentityServerResponse(from: subItemData)
            default:
                break
            }
        }
        
        return result
    }
    
    private static func decodeUserInformation(from data: Data) throws -> (maxPDUSize: UInt32?, implementationClassUID: String?, implementationVersionName: String?) {
        let result = try decodeUserInformationFull(from: data)
        return (result.maxPDUSize, result.implementationClassUID, result.implementationVersionName)
    }
    
    /// Decodes User Identity from a sub-item
    ///
    /// Reference: PS3.7 Section D.3.3.7.1 - Sub-item Structure (A-ASSOCIATE-RQ)
    private static func decodeUserIdentity(from data: Data) throws -> UserIdentity {
        guard data.count >= 6 else {
            throw DICOMNetworkError.decodingFailed("User Identity sub-item too short")
        }
        
        var offset = data.startIndex
        
        // User-Identity-Type (1 byte)
        let identityTypeByte = data[offset]
        guard let identityType = UserIdentityType(rawValue: identityTypeByte) else {
            throw DICOMNetworkError.decodingFailed("Unknown User Identity Type: \(identityTypeByte)")
        }
        offset += 1
        
        // Positive-response-requested (1 byte)
        let positiveResponseRequested = data[offset] != 0
        offset += 1
        
        // Primary-field-length (2 bytes, big endian)
        let primaryLength = readUInt16BigEndian(from: data, at: offset)
        offset += 2
        
        guard offset + Int(primaryLength) <= data.endIndex else {
            throw DICOMNetworkError.decodingFailed("User Identity primary field extends beyond data")
        }
        
        // Primary-field
        let primaryField = Data(data[offset ..< offset + Int(primaryLength)])
        offset += Int(primaryLength)
        
        // Secondary-field (only for usernameAndPasscode type)
        var secondaryField: Data?
        if identityType == .usernameAndPasscode && offset + 2 <= data.endIndex {
            let secondaryLength = readUInt16BigEndian(from: data, at: offset)
            offset += 2
            
            if secondaryLength > 0 && offset + Int(secondaryLength) <= data.endIndex {
                secondaryField = Data(data[offset ..< offset + Int(secondaryLength)])
            }
        }
        
        return UserIdentity(
            identityType: identityType,
            positiveResponseRequested: positiveResponseRequested,
            primaryField: primaryField,
            secondaryField: secondaryField
        )
    }
    
    /// Decodes User Identity Server Response from a sub-item
    ///
    /// Reference: PS3.7 Section D.3.3.7.2 - Sub-item Structure (A-ASSOCIATE-AC)
    private static func decodeUserIdentityServerResponse(from data: Data) throws -> UserIdentityServerResponse {
        guard data.count >= 2 else {
            throw DICOMNetworkError.decodingFailed("User Identity Server Response sub-item too short")
        }
        
        var offset = data.startIndex
        
        // Server-response-length (2 bytes, big endian)
        let responseLength = readUInt16BigEndian(from: data, at: offset)
        offset += 2
        
        guard offset + Int(responseLength) <= data.endIndex else {
            throw DICOMNetworkError.decodingFailed("User Identity Server Response extends beyond data")
        }
        
        // Server-response
        let serverResponse = Data(data[offset ..< offset + Int(responseLength)])
        
        return UserIdentityServerResponse(serverResponse: serverResponse)
    }
    
    private static func decodeAssociateAccept(from data: Data) throws -> AssociateAcceptPDU {
        var offset = data.startIndex
        
        guard data.count >= 68 else {
            throw DICOMNetworkError.decodingFailed("A-ASSOCIATE-AC too short")
        }
        
        // Protocol Version (2 bytes)
        let protocolVersion = readUInt16BigEndian(from: data, at: offset)
        offset += 2
        
        // Reserved (2 bytes)
        offset += 2
        
        // Called AE Title (16 bytes)
        // Per PS3.8 §9.3.3 these fixed fields are "Reserved" in A-ASSOCIATE-AC and NOT significant.
        // Many SCPs (including older dcm4chee variants) send all-spaces here, so we use a lenient
        // fallback instead of throwing a hard decode error.
        let calledAEData = Data(data[offset ..< offset + 16])
        let calledAETitle = AETitle.from(data: calledAEData) ?? AETitle(stringLiteral: "UNKNOWN")
        offset += 16
        
        // Calling AE Title (16 bytes) — also reserved/not significant in A-ASSOCIATE-AC
        let callingAEData = Data(data[offset ..< offset + 16])
        let callingAETitle = AETitle.from(data: callingAEData) ?? AETitle(stringLiteral: "UNKNOWN")
        offset += 16
        
        // Reserved (32 bytes)
        offset += 32
        
        // Parse variable items
        var applicationContextName = AssociateRequestPDU.dicomApplicationContextName
        var presentationContexts: [AcceptedPresentationContext] = []
        var maxPDUSize: UInt32 = defaultMaxPDUSize
        var implementationClassUID = ""
        var implementationVersionName: String?
        var userIdentityServerResponse: UserIdentityServerResponse?
        var roleSelections: [SCPSCURoleSelection] = []
        var extendedNegotiations: [SOPClassExtendedNegotiation] = []
        
        while offset < data.endIndex {
            guard offset + 4 <= data.endIndex else { break }
            
            let itemType = data[offset]
            offset += 2 // Type + Reserved
            
            let itemLength = readUInt16BigEndian(from: data, at: offset)
            offset += 2
            
            guard offset + Int(itemLength) <= data.endIndex else { break }
            let itemData = Data(data[offset ..< offset + Int(itemLength)])
            offset += Int(itemLength)
            
            switch itemType {
            case 0x10: // Application Context
                applicationContextName = String(data: itemData, encoding: .ascii) ?? applicationContextName
                
            case 0x21: // Presentation Context (AC)
                if let context = decodePresentationContextAC(from: itemData) {
                    presentationContexts.append(context)
                }
                
            case 0x50: // User Information
                let userInfo = try decodeUserInformationFull(from: itemData)
                maxPDUSize = userInfo.maxPDUSize ?? maxPDUSize
                implementationClassUID = userInfo.implementationClassUID ?? implementationClassUID
                implementationVersionName = userInfo.implementationVersionName
                userIdentityServerResponse = userInfo.userIdentityServerResponse
                roleSelections = userInfo.roleSelections
                extendedNegotiations = userInfo.extendedNegotiations
                
            default:
                break
            }
        }
        
        return AssociateAcceptPDU(
            protocolVersion: protocolVersion,
            calledAETitle: calledAETitle,
            callingAETitle: callingAETitle,
            applicationContextName: applicationContextName,
            presentationContexts: presentationContexts,
            maxPDUSize: maxPDUSize,
            implementationClassUID: implementationClassUID,
            implementationVersionName: implementationVersionName,
            userIdentityServerResponse: userIdentityServerResponse,
            roleSelections: roleSelections,
            extendedNegotiations: extendedNegotiations
        )
    }
    
    private static func decodePresentationContextAC(from data: Data) -> AcceptedPresentationContext? {
        guard data.count >= 4 else { return nil }
        
        var offset = data.startIndex
        
        let contextID = data[offset]
        offset += 1
        offset += 1 // Reserved
        
        let resultByte = data[offset]
        let result = PresentationContextResult(rawValue: resultByte) ?? .noReasonProviderRejection
        offset += 2 // Result + Reserved
        
        var transferSyntax: String?
        
        while offset < data.endIndex {
            guard offset + 4 <= data.endIndex else { break }
            
            let subItemType = data[offset]
            offset += 2
            
            let subItemLength = readUInt16BigEndian(from: data, at: offset)
            offset += 2
            
            guard offset + Int(subItemLength) <= data.endIndex else { break }
            let subItemData = Data(data[offset ..< offset + Int(subItemLength)])
            offset += Int(subItemLength)
            
            if subItemType == 0x40 { // Transfer Syntax
                transferSyntax = String(data: subItemData, encoding: .ascii)
            }
        }
        
        // PS3.8 Table 9-18: the Transfer Syntax sub-item is not significant
        // (and "shall not be tested") when the Result/Reason is not acceptance.
        if result != .acceptance || transferSyntax?.isEmpty == true {
            transferSyntax = nil
        }
        
        return AcceptedPresentationContext(id: contextID, result: result, transferSyntax: transferSyntax)
    }
    
    private static func decodeAssociateReject(from data: Data) throws -> AssociateRejectPDU {
        guard data.count >= 4 else {
            throw DICOMNetworkError.decodingFailed("A-ASSOCIATE-RJ too short")
        }
        
        // Reserved (1 byte)
        // Result (1 byte)
        let resultByte = data[data.startIndex + 1]
        guard let result = AssociateRejectResult(rawValue: resultByte) else {
            throw DICOMNetworkError.decodingFailed("Invalid reject result: \(resultByte)")
        }
        
        // Source (1 byte)
        let sourceByte = data[data.startIndex + 2]
        guard let source = AssociateRejectSource(rawValue: sourceByte) else {
            throw DICOMNetworkError.decodingFailed("Invalid reject source: \(sourceByte)")
        }
        
        // Reason (1 byte)
        let reason = data[data.startIndex + 3]
        
        return AssociateRejectPDU(result: result, source: source, reason: reason)
    }
    
    private static func decodeDataTransfer(from data: Data) throws -> DataTransferPDU {
        var offset = data.startIndex
        var pdvs: [PresentationDataValue] = []
        
        while offset < data.endIndex {
            guard offset + 4 <= data.endIndex else { break }
            
            // PDV Item Length (4 bytes, big endian)
            let itemLength = readUInt32BigEndian(from: data, at: offset)
            offset += 4
            
            guard offset + Int(itemLength) <= data.endIndex else {
                throw DICOMNetworkError.decodingFailed("PDV item extends beyond PDU")
            }
            
            guard itemLength >= 2 else {
                throw DICOMNetworkError.decodingFailed("PDV item too short")
            }
            
            // Presentation Context ID (1 byte)
            let contextID = data[offset]
            offset += 1
            
            // Message Control Header (1 byte)
            let controlHeader = data[offset]
            offset += 1
            
            let isCommand = (controlHeader & 0x01) != 0
            let isLastFragment = (controlHeader & 0x02) != 0
            
            // Data payload
            let dataLength = Int(itemLength) - 2
            let pdvData = Data(data[offset ..< offset + dataLength])
            offset += dataLength
            
            let pdv = PresentationDataValue(
                presentationContextID: contextID,
                isCommand: isCommand,
                isLastFragment: isLastFragment,
                data: pdvData
            )
            pdvs.append(pdv)
        }
        
        return DataTransferPDU(presentationDataValues: pdvs)
    }
    
    private static func decodeAbort(from data: Data) throws -> AbortPDU {
        guard data.count >= 4 else {
            throw DICOMNetworkError.decodingFailed("A-ABORT too short")
        }
        
        // Reserved (2 bytes)
        // Source (1 byte)
        let sourceByte = data[data.startIndex + 2]
        let source = AbortSource(rawValue: sourceByte) ?? .serviceProvider
        
        // Reason (1 byte)
        let reason = data[data.startIndex + 3]
        
        return AbortPDU(source: source, reason: reason)
    }
}
