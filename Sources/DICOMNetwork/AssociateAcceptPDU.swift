import Foundation
// NEMA-verified: 2026a, checked 2026-09-28 — A-ASSOCIATE-AC layout compared with PS3.8 2026a Tables 9-17..9-20 (a Transfer Syntax sub-item is now present in every Presentation Context item, Table 9-18) and PS3.7 Tables D.3-2/D.3-4 (length limits enforced); 2026-10-01: SOP Class Extended Negotiation answers (56H) per PS3.7 Table D.3-11 / D.3.3.5

/// A-ASSOCIATE-AC PDU (Association Accept)
///
/// Used by the acceptor (SCP) to indicate acceptance of an association request.
///
/// Reference: PS3.8 Section 9.3.3
public struct AssociateAcceptPDU: PDU, Sendable, Hashable {
    public let pduType: PDUType = .associateAccept
    
    /// Protocol version (always 1)
    public let protocolVersion: UInt16
    
    /// Called AE Title (the receiving application entity)
    public let calledAETitle: AETitle
    
    /// Calling AE Title (the initiating application entity)
    public let callingAETitle: AETitle
    
    /// Application Context Name
    public let applicationContextName: String
    
    /// Accepted presentation contexts with negotiation results
    public let presentationContexts: [AcceptedPresentationContext]
    
    /// Maximum PDU size that the acceptor can receive
    public let maxPDUSize: UInt32
    
    /// Implementation Class UID of the acceptor
    public let implementationClassUID: String
    
    /// Implementation Version Name of the acceptor (optional)
    public let implementationVersionName: String?
    
    /// User identity server response (optional)
    ///
    /// Included when the SCU requested a positive response for user identity
    /// negotiation and the SCP accepted the authentication.
    ///
    /// Reference: PS3.7 Section D.3.3.7.2 - Server Response
    public let userIdentityServerResponse: UserIdentityServerResponse?
    
    /// SCP/SCU Role Selections granted by the acceptor (optional)
    ///
    /// Per PS3.7 D.3.3.4.2 the acceptor answers each proposed role selection;
    /// a missing answer means the default roles apply for that SOP Class.
    public let roleSelections: [SCPSCURoleSelection]

    /// SOP Class Extended Negotiation answers of the acceptor (optional)
    ///
    /// Per PS3.7 D.3.3.5 the acceptor returns the sub-item only for SOP Classes
    /// whose extended negotiation was offered; a missing answer means the
    /// Service Class default applies.
    public let extendedNegotiations: [SOPClassExtendedNegotiation]
    
    /// Creates an A-ASSOCIATE-AC PDU
    public init(
        protocolVersion: UInt16 = 1,
        calledAETitle: AETitle,
        callingAETitle: AETitle,
        applicationContextName: String = AssociateRequestPDU.dicomApplicationContextName,
        presentationContexts: [AcceptedPresentationContext],
        maxPDUSize: UInt32,
        implementationClassUID: String,
        implementationVersionName: String? = nil,
        userIdentityServerResponse: UserIdentityServerResponse? = nil,
        roleSelections: [SCPSCURoleSelection] = []
    ) {
        self.init(
            protocolVersion: protocolVersion, calledAETitle: calledAETitle, callingAETitle: callingAETitle,
            applicationContextName: applicationContextName, presentationContexts: presentationContexts,
            maxPDUSize: maxPDUSize, implementationClassUID: implementationClassUID,
            implementationVersionName: implementationVersionName,
            userIdentityServerResponse: userIdentityServerResponse,
            roleSelections: roleSelections, extendedNegotiations: [])
    }

    /// Creates an A-ASSOCIATE-AC PDU answering SOP Class Extended Negotiation
    /// sub-items (PS3.7 D.3.3.5, Table D.3-11; added 2026-10-01).
    public init(
        protocolVersion: UInt16 = 1,
        calledAETitle: AETitle,
        callingAETitle: AETitle,
        applicationContextName: String = AssociateRequestPDU.dicomApplicationContextName,
        presentationContexts: [AcceptedPresentationContext],
        maxPDUSize: UInt32,
        implementationClassUID: String,
        implementationVersionName: String? = nil,
        userIdentityServerResponse: UserIdentityServerResponse? = nil,
        roleSelections: [SCPSCURoleSelection] = [],
        extendedNegotiations: [SOPClassExtendedNegotiation]
    ) {
        self.protocolVersion = protocolVersion
        self.calledAETitle = calledAETitle
        self.callingAETitle = callingAETitle
        self.applicationContextName = applicationContextName
        self.presentationContexts = presentationContexts
        self.maxPDUSize = maxPDUSize
        self.implementationClassUID = implementationClassUID
        self.implementationVersionName = implementationVersionName
        self.userIdentityServerResponse = userIdentityServerResponse
        self.roleSelections = roleSelections
        self.extendedNegotiations = extendedNegotiations
    }
    
    /// Encodes the PDU for network transmission
    ///
    /// - Throws: `DICOMNetworkError.encodingFailed` if the Implementation
    ///   Class UID exceeds 64 bytes (PS3.5 UI) or the Implementation Version
    ///   Name is not 1-16 characters (PS3.7 Table D.3-4)
    ///
    /// Reference: PS3.8 Section 9.3.3
    public func encode() throws -> Data {
        try validateImplementationSubItems(
            classUID: implementationClassUID, versionName: implementationVersionName)
        
        var data = Data()
        
        // Build the PDU variable field first
        var variableField = Data()
        
        // Protocol Version (2 bytes)
        variableField.append(contentsOf: withUnsafeBytes(of: protocolVersion.bigEndian) { Array($0) })
        
        // Reserved (2 bytes)
        variableField.append(contentsOf: [0x00, 0x00])
        
        // Called AE Title (16 bytes)
        variableField.append(calledAETitle.data)
        
        // Calling AE Title (16 bytes)
        variableField.append(callingAETitle.data)
        
        // Reserved (32 bytes)
        variableField.append(contentsOf: [UInt8](repeating: 0x00, count: 32))
        
        // Application Context Item
        variableField.append(encodeApplicationContextItem())
        
        // Presentation Context Items
        for context in presentationContexts {
            variableField.append(encodePresentationContextItem(context))
        }
        
        // User Information Item
        variableField.append(encodeUserInformationItem())
        
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
    
    private func encodeApplicationContextItem() -> Data {
        var item = Data()
        item.append(0x10)  // Item Type
        item.append(0x00)  // Reserved
        
        let nameData = Data(applicationContextName.utf8)
        let itemLength = UInt16(nameData.count)
        item.append(contentsOf: withUnsafeBytes(of: itemLength.bigEndian) { Array($0) })
        item.append(nameData)
        
        return item
    }
    
    private func encodePresentationContextItem(_ context: AcceptedPresentationContext) -> Data {
        var item = Data()
        
        // Build content first
        var content = Data()
        content.append(context.id)  // Presentation Context ID
        content.append(0x00)  // Reserved
        content.append(context.result.rawValue)  // Result/Reason
        content.append(0x00)  // Reserved
        
        // Transfer Syntax Sub-Item: PS3.8 Table 9-18 requires exactly one in
        // every Presentation Context item. When the Result/Reason is not
        // acceptance the sub-item "shall not be significant", so a rejected
        // context carries an empty-name sub-item (item-length 0).
        var subItem = Data()
        subItem.append(0x40)  // Sub-Item Type
        subItem.append(0x00)  // Reserved
        
        let tsData = Data((context.transferSyntax ?? "").utf8)
        let tsLength = UInt16(tsData.count)
        subItem.append(contentsOf: withUnsafeBytes(of: tsLength.bigEndian) { Array($0) })
        subItem.append(tsData)
        
        content.append(subItem)
        
        // Item Type (0x21 for Presentation Context AC)
        item.append(0x21)
        item.append(0x00)  // Reserved
        
        let itemLength = UInt16(content.count)
        item.append(contentsOf: withUnsafeBytes(of: itemLength.bigEndian) { Array($0) })
        item.append(content)
        
        return item
    }
    
    private func encodeUserInformationItem() -> Data {
        var item = Data()
        
        // Build sub-items
        var subItems = Data()
        
        // Maximum Length Sub-Item
        var maxLengthSubItem = Data()
        maxLengthSubItem.append(0x51)
        maxLengthSubItem.append(0x00)
        let length = UInt16(4)
        maxLengthSubItem.append(contentsOf: withUnsafeBytes(of: length.bigEndian) { Array($0) })
        maxLengthSubItem.append(contentsOf: withUnsafeBytes(of: maxPDUSize.bigEndian) { Array($0) })
        subItems.append(maxLengthSubItem)
        
        // Implementation Class UID Sub-Item
        var implClassSubItem = Data()
        implClassSubItem.append(0x52)
        implClassSubItem.append(0x00)
        let uidData = Data(implementationClassUID.utf8)
        let uidLength = UInt16(uidData.count)
        implClassSubItem.append(contentsOf: withUnsafeBytes(of: uidLength.bigEndian) { Array($0) })
        implClassSubItem.append(uidData)
        subItems.append(implClassSubItem)
        
        // Implementation Version Name Sub-Item (optional)
        if let versionName = implementationVersionName {
            var versionSubItem = Data()
            versionSubItem.append(0x55)
            versionSubItem.append(0x00)
            let versionData = Data(versionName.utf8)
            let versionLength = UInt16(versionData.count)
            versionSubItem.append(contentsOf: withUnsafeBytes(of: versionLength.bigEndian) { Array($0) })
            versionSubItem.append(versionData)
            subItems.append(versionSubItem)
        }
        
        // SCP/SCU Role Selection Sub-Items (optional, PS3.7 D.3.3.4.2)
        for role in roleSelections {
            subItems.append(role.encode())
        }

        // SOP Class Extended Negotiation Sub-Items (optional, PS3.7 D.3.3.5)
        for negotiation in extendedNegotiations {
            subItems.append(negotiation.encode())
        }
        
        // User Identity Server Response Sub-Item (optional)
        if let serverResponse = userIdentityServerResponse {
            subItems.append(serverResponse.encode())
        }
        
        // User Information Item
        item.append(0x50)  // Item Type
        item.append(0x00)  // Reserved
        let itemLength = UInt16(subItems.count)
        item.append(contentsOf: withUnsafeBytes(of: itemLength.bigEndian) { Array($0) })
        item.append(subItems)
        
        return item
    }
    
    /// The SOP Class Extended Negotiation answer for a SOP Class, if the acceptor sent one
    public func extendedNegotiation(for sopClassUID: String) -> SOPClassExtendedNegotiation? {
        extendedNegotiations.first { $0.sopClassUID == sopClassUID }
    }

    /// The role selection answer for a SOP Class, if the acceptor sent one
    public func roleSelection(for sopClassUID: String) -> SCPSCURoleSelection? {
        roleSelections.first { $0.sopClassUID == sopClassUID }
    }
    
    /// Gets the accepted transfer syntax for a given presentation context ID
    public func acceptedTransferSyntax(forContextID id: UInt8) -> String? {
        presentationContexts.first(where: { $0.id == id && $0.isAccepted })?.transferSyntax
    }
    
    /// Gets all accepted presentation context IDs
    public var acceptedContextIDs: [UInt8] {
        presentationContexts.filter { $0.isAccepted }.map { $0.id }
    }
}

// MARK: - CustomStringConvertible
extension AssociateAcceptPDU: CustomStringConvertible {
    public var description: String {
        let acceptedCount = presentationContexts.filter { $0.isAccepted }.count
        var desc = """
        A-ASSOCIATE-AC:
          Called AE Title: \(calledAETitle)
          Calling AE Title: \(callingAETitle)
          Application Context: \(applicationContextName)
          Presentation Contexts: \(presentationContexts.count) (\(acceptedCount) accepted)
          Max PDU Size: \(maxPDUSize)
          Implementation Class UID: \(implementationClassUID)
          Implementation Version Name: \(implementationVersionName ?? "(none)")
        """
        if userIdentityServerResponse != nil {
            desc += "\n  User Identity Response: present"
        }
        return desc
    }
}
