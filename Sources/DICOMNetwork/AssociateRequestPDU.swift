import Foundation
// NEMA-verified: 2026a, checked 2026-09-28 — A-ASSOCIATE-RQ layout compared with PS3.8 2026a Tables 9-11..9-16 and Annex D.1-1; Application Context Name per PS3.7 A.2.1; Implementation Class UID / Version Name limits per PS3.7 Tables D.3-1/D.3-3 and PS3.5 UI (enforced); 2026-10-01: SOP Class Extended Negotiation sub-items (56H) encoded per PS3.7 Table D.3-11

/// A-ASSOCIATE-RQ PDU (Association Request)
///
/// Used by the requestor (SCU) to request an association with an acceptor (SCP).
///
/// Reference: PS3.8 Section 9.3.2
public struct AssociateRequestPDU: PDU, Sendable, Hashable {
    public let pduType: PDUType = .associateRequest
    
    /// Protocol version
    ///
    /// Always 1 when built locally. A decoded PDU carries the peer's value;
    /// PS3.8 Table 9-11 bytes 7-8: "A receiver of this PDU implementing only
    /// this version of the DICOM UL protocol shall only test that bit 0 is set."
    public let protocolVersion: UInt16
    
    /// Called AE Title (the receiving application entity)
    public let calledAETitle: AETitle
    
    /// Calling AE Title (the initiating application entity)
    public let callingAETitle: AETitle
    
    /// Application Context Name
    ///
    /// For DICOM, this is always "1.2.840.10008.3.1.1.1"
    public let applicationContextName: String
    
    /// Proposed presentation contexts
    public let presentationContexts: [PresentationContext]
    
    /// Maximum PDU size that the requestor can receive
    public let maxPDUSize: UInt32
    
    /// Implementation Class UID
    public let implementationClassUID: String
    
    /// Implementation Version Name (optional)
    public let implementationVersionName: String?
    
    /// User identity for authentication (optional)
    ///
    /// Reference: PS3.7 Section D.3.3.7 - User Identity Negotiation
    public let userIdentity: UserIdentity?
    
    /// Proposed SCP/SCU Role Selections (optional)
    ///
    /// One entry per Abstract Syntax for which the requestor wants a role other
    /// than the default (SCU only). Required for C-GET storage contexts.
    ///
    /// Reference: PS3.7 Section D.3.3.4 - SCP/SCU Role Selection Negotiation
    public let roleSelections: [SCPSCURoleSelection]

    /// Proposed SOP Class Extended Negotiation sub-items (optional)
    ///
    /// Reference: PS3.7 Section D.3.3.5 - SOP Class Extended Negotiation
    public let extendedNegotiations: [SOPClassExtendedNegotiation]
    
    /// DICOM Application Context Name UID
    ///
    /// Reference: PS3.7 Annex A
    public static let dicomApplicationContextName = "1.2.840.10008.3.1.1.1"
    
    /// Creates an A-ASSOCIATE-RQ PDU
    ///
    /// - Parameters:
    ///   - calledAETitle: The AE Title of the acceptor (SCP)
    ///   - callingAETitle: The AE Title of the requestor (SCU)
    ///   - presentationContexts: The proposed presentation contexts
    ///   - maxPDUSize: Maximum PDU size the requestor can receive
    ///   - implementationClassUID: The Implementation Class UID
    ///   - implementationVersionName: The Implementation Version Name (optional)
    ///   - userIdentity: User identity for authentication (optional)
    ///   - applicationContextName: Application Context Name (defaults to DICOM)
    ///   - roleSelections: Proposed SCP/SCU Role Selections (optional)
    public init(
        calledAETitle: AETitle,
        callingAETitle: AETitle,
        presentationContexts: [PresentationContext],
        maxPDUSize: UInt32 = defaultMaxPDUSize,
        implementationClassUID: String,
        implementationVersionName: String? = nil,
        userIdentity: UserIdentity? = nil,
        applicationContextName: String = dicomApplicationContextName,
        roleSelections: [SCPSCURoleSelection] = []
    ) {
        self.init(
            calledAETitle: calledAETitle, callingAETitle: callingAETitle,
            presentationContexts: presentationContexts, maxPDUSize: maxPDUSize,
            implementationClassUID: implementationClassUID,
            implementationVersionName: implementationVersionName,
            userIdentity: userIdentity, applicationContextName: applicationContextName,
            roleSelections: roleSelections, extendedNegotiations: [])
    }

    /// Creates an A-ASSOCIATE-RQ PDU proposing SOP Class Extended Negotiation
    /// sub-items (PS3.7 D.3.3.5, Table D.3-11; added 2026-10-01).
    public init(
        calledAETitle: AETitle,
        callingAETitle: AETitle,
        presentationContexts: [PresentationContext],
        maxPDUSize: UInt32 = defaultMaxPDUSize,
        implementationClassUID: String,
        implementationVersionName: String? = nil,
        userIdentity: UserIdentity? = nil,
        applicationContextName: String = dicomApplicationContextName,
        roleSelections: [SCPSCURoleSelection] = [],
        extendedNegotiations: [SOPClassExtendedNegotiation]
    ) {
        self.init(
            protocolVersion: 1,
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
    
    /// Creates an A-ASSOCIATE-RQ PDU carrying an explicit Protocol-version
    ///
    /// Used by the decoder to preserve the peer's value (and by tests to
    /// build a request with bit 0 clear).
    init(
        protocolVersion: UInt16,
        calledAETitle: AETitle,
        callingAETitle: AETitle,
        presentationContexts: [PresentationContext],
        maxPDUSize: UInt32 = defaultMaxPDUSize,
        implementationClassUID: String,
        implementationVersionName: String? = nil,
        userIdentity: UserIdentity? = nil,
        applicationContextName: String = dicomApplicationContextName,
        roleSelections: [SCPSCURoleSelection] = [],
        extendedNegotiations: [SOPClassExtendedNegotiation] = []
    ) {
        self.protocolVersion = protocolVersion
        self.calledAETitle = calledAETitle
        self.callingAETitle = callingAETitle
        self.presentationContexts = presentationContexts
        self.maxPDUSize = maxPDUSize
        self.implementationClassUID = implementationClassUID
        self.implementationVersionName = implementationVersionName
        self.userIdentity = userIdentity
        self.applicationContextName = applicationContextName
        self.roleSelections = roleSelections
        self.extendedNegotiations = extendedNegotiations
    }
    
    /// Whether the Protocol-version is acceptable to this implementation
    ///
    /// PS3.8 Table 9-11: only bit 0 (version 1) is tested.
    var isProtocolVersionSupported: Bool {
        (protocolVersion & 0x0001) != 0
    }
    
    /// Encodes the PDU for network transmission
    ///
    /// - Throws: `DICOMNetworkError.encodingFailed` if the Implementation
    ///   Class UID exceeds 64 bytes (PS3.5 UI) or the Implementation Version
    ///   Name is not 1-16 characters (PS3.7 Table D.3-4)
    ///
    /// Reference: PS3.8 Section 9.3.2
    public func encode() throws -> Data {
        try validateImplementationSubItems(
            classUID: implementationClassUID, versionName: implementationVersionName)
        
        var data = Data()
        
        // Build the PDU variable field first to calculate length
        var variableField = Data()
        
        // Protocol Version (2 bytes)
        variableField.append(contentsOf: withUnsafeBytes(of: protocolVersion.bigEndian) { Array($0) })
        
        // Reserved (2 bytes)
        variableField.append(contentsOf: [0x00, 0x00])
        
        // Called AE Title (16 bytes, space padded)
        variableField.append(calledAETitle.data)
        
        // Calling AE Title (16 bytes, space padded)
        variableField.append(callingAETitle.data)
        
        // Reserved (32 bytes)
        variableField.append(contentsOf: [UInt8](repeating: 0x00, count: 32))
        
        // Application Context Item
        variableField.append(try encodeApplicationContextItem())
        
        // Presentation Context Items
        for context in presentationContexts {
            variableField.append(try encodePresentationContextItem(context))
        }
        
        // User Information Item
        variableField.append(try encodeUserInformationItem())
        
        // Now build the full PDU
        // PDU Type (1 byte)
        data.append(pduType.rawValue)
        
        // Reserved (1 byte)
        data.append(0x00)
        
        // PDU Length (4 bytes, big endian)
        let pduLength = UInt32(variableField.count)
        data.append(contentsOf: withUnsafeBytes(of: pduLength.bigEndian) { Array($0) })
        
        // Variable field
        data.append(variableField)
        
        return data
    }
    
    // MARK: - Private Encoding Methods
    
    private func encodeApplicationContextItem() throws -> Data {
        var item = Data()
        
        // Item Type (1 byte) - 0x10 for Application Context
        item.append(0x10)
        
        // Reserved (1 byte)
        item.append(0x00)
        
        // Item Length (2 bytes, big endian)
        let nameData = Data(applicationContextName.utf8)
        let itemLength = UInt16(nameData.count)
        item.append(contentsOf: withUnsafeBytes(of: itemLength.bigEndian) { Array($0) })
        
        // Application Context Name
        item.append(nameData)
        
        return item
    }
    
    private func encodePresentationContextItem(_ context: PresentationContext) throws -> Data {
        var item = Data()
        
        // Build the item content first
        var content = Data()
        
        // Presentation Context ID (1 byte)
        content.append(context.id)
        
        // Reserved (3 bytes)
        content.append(contentsOf: [0x00, 0x00, 0x00])
        
        // Abstract Syntax Sub-Item
        content.append(try encodeAbstractSyntaxSubItem(context.abstractSyntax))
        
        // Transfer Syntax Sub-Items
        for transferSyntax in context.transferSyntaxes {
            content.append(try encodeTransferSyntaxSubItem(transferSyntax))
        }
        
        // Item Type (1 byte) - 0x20 for Presentation Context (RQ)
        item.append(0x20)
        
        // Reserved (1 byte)
        item.append(0x00)
        
        // Item Length (2 bytes, big endian)
        let itemLength = UInt16(content.count)
        item.append(contentsOf: withUnsafeBytes(of: itemLength.bigEndian) { Array($0) })
        
        // Content
        item.append(content)
        
        return item
    }
    
    private func encodeAbstractSyntaxSubItem(_ uid: String) throws -> Data {
        var subItem = Data()
        
        // Sub-Item Type (1 byte) - 0x30 for Abstract Syntax
        subItem.append(0x30)
        
        // Reserved (1 byte)
        subItem.append(0x00)
        
        // Sub-Item Length (2 bytes, big endian)
        let uidData = Data(uid.utf8)
        let subItemLength = UInt16(uidData.count)
        subItem.append(contentsOf: withUnsafeBytes(of: subItemLength.bigEndian) { Array($0) })
        
        // Abstract Syntax Name (UID)
        subItem.append(uidData)
        
        return subItem
    }
    
    private func encodeTransferSyntaxSubItem(_ uid: String) throws -> Data {
        var subItem = Data()
        
        // Sub-Item Type (1 byte) - 0x40 for Transfer Syntax
        subItem.append(0x40)
        
        // Reserved (1 byte)
        subItem.append(0x00)
        
        // Sub-Item Length (2 bytes, big endian)
        let uidData = Data(uid.utf8)
        let subItemLength = UInt16(uidData.count)
        subItem.append(contentsOf: withUnsafeBytes(of: subItemLength.bigEndian) { Array($0) })
        
        // Transfer Syntax Name (UID)
        subItem.append(uidData)
        
        return subItem
    }
    
    private func encodeUserInformationItem() throws -> Data {
        var item = Data()
        
        // Build sub-items first
        var subItems = Data()
        
        // Maximum Length Sub-Item (required)
        subItems.append(encodeMaxLengthSubItem())
        
        // Implementation Class UID Sub-Item (required)
        subItems.append(encodeImplementationClassUIDSubItem())
        
        // Implementation Version Name Sub-Item (optional)
        if let versionName = implementationVersionName {
            subItems.append(encodeImplementationVersionNameSubItem(versionName))
        }
        
        // SCP/SCU Role Selection Sub-Items (optional, PS3.7 D.3.3.4)
        for role in roleSelections {
            subItems.append(role.encode())
        }

        // SOP Class Extended Negotiation Sub-Items (optional, PS3.7 D.3.3.5)
        for negotiation in extendedNegotiations {
            subItems.append(negotiation.encode())
        }
        
        // User Identity Sub-Item (optional)
        if let userIdentity = userIdentity {
            subItems.append(userIdentity.encode())
        }
        
        // Item Type (1 byte) - 0x50 for User Information
        item.append(0x50)
        
        // Reserved (1 byte)
        item.append(0x00)
        
        // Item Length (2 bytes, big endian)
        let itemLength = UInt16(subItems.count)
        item.append(contentsOf: withUnsafeBytes(of: itemLength.bigEndian) { Array($0) })
        
        // Sub-Items
        item.append(subItems)
        
        return item
    }
    
    private func encodeMaxLengthSubItem() -> Data {
        var subItem = Data()
        
        // Sub-Item Type (1 byte) - 0x51 for Maximum Length
        subItem.append(0x51)
        
        // Reserved (1 byte)
        subItem.append(0x00)
        
        // Sub-Item Length (2 bytes, big endian) - always 4 for max length
        let length = UInt16(4)
        subItem.append(contentsOf: withUnsafeBytes(of: length.bigEndian) { Array($0) })
        
        // Maximum Length Received (4 bytes, big endian)
        subItem.append(contentsOf: withUnsafeBytes(of: maxPDUSize.bigEndian) { Array($0) })
        
        return subItem
    }
    
    private func encodeImplementationClassUIDSubItem() -> Data {
        var subItem = Data()
        
        // Sub-Item Type (1 byte) - 0x52 for Implementation Class UID
        subItem.append(0x52)
        
        // Reserved (1 byte)
        subItem.append(0x00)
        
        // Sub-Item Length (2 bytes, big endian)
        let uidData = Data(implementationClassUID.utf8)
        let length = UInt16(uidData.count)
        subItem.append(contentsOf: withUnsafeBytes(of: length.bigEndian) { Array($0) })
        
        // Implementation Class UID
        subItem.append(uidData)
        
        return subItem
    }
    
    private func encodeImplementationVersionNameSubItem(_ versionName: String) -> Data {
        var subItem = Data()
        
        // Sub-Item Type (1 byte) - 0x55 for Implementation Version Name
        subItem.append(0x55)
        
        // Reserved (1 byte)
        subItem.append(0x00)
        
        // Sub-Item Length (2 bytes, big endian)
        let nameData = Data(versionName.utf8)
        let length = UInt16(nameData.count)
        subItem.append(contentsOf: withUnsafeBytes(of: length.bigEndian) { Array($0) })
        
        // Implementation Version Name
        subItem.append(nameData)
        
        return subItem
    }
}

// MARK: - CustomStringConvertible
extension AssociateRequestPDU: CustomStringConvertible {
    public var description: String {
        var desc = """
        A-ASSOCIATE-RQ:
          Called AE Title: \(calledAETitle)
          Calling AE Title: \(callingAETitle)
          Application Context: \(applicationContextName)
          Presentation Contexts: \(presentationContexts.count)
          Max PDU Size: \(maxPDUSize)
          Implementation Class UID: \(implementationClassUID)
          Implementation Version Name: \(implementationVersionName ?? "(none)")
        """
        if let identity = userIdentity {
            desc += "\n  User Identity: \(identity)"
        }
        return desc
    }
}
