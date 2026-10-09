import Testing
import Foundation
@testable import DICOMNetwork

// Helper function to read big-endian UInt32 from data
fileprivate func readUInt32BigEndian(from data: Data, at offset: Int) -> UInt32 {
    return (UInt32(data[offset]) << 24) |
           (UInt32(data[offset + 1]) << 16) |
           (UInt32(data[offset + 2]) << 8) |
           UInt32(data[offset + 3])
}

@Suite("Associate Request PDU Tests")
struct AssociateRequestPDUTests {
    
    @Test("Associate Request PDU creation")
    func testAssociateRequestCreation() throws {
        let context = try PresentationContext(
            id: 1,
            abstractSyntax: "1.2.840.10008.5.1.4.1.1.7",
            transferSyntaxes: ["1.2.840.10008.1.2.1"]
        )
        
        let request = AssociateRequestPDU(
            calledAETitle: try AETitle("PACS_SERVER"),
            callingAETitle: try AETitle("MY_CLIENT"),
            presentationContexts: [context],
            implementationClassUID: "1.2.3.4.5.6.7.8.9"
        )
        
        #expect(request.pduType == .associateRequest)
        #expect(request.calledAETitle.value == "PACS_SERVER")
        #expect(request.callingAETitle.value == "MY_CLIENT")
        #expect(request.presentationContexts.count == 1)
        #expect(request.maxPDUSize == defaultMaxPDUSize)
        #expect(request.implementationClassUID == "1.2.3.4.5.6.7.8.9")
        #expect(request.applicationContextName == AssociateRequestPDU.dicomApplicationContextName)
    }
    
    @Test("Associate Request PDU encoding")
    func testAssociateRequestEncoding() throws {
        let context = try PresentationContext(
            id: 1,
            abstractSyntax: "1.2.840.10008.5.1.4.1.1.7",
            transferSyntaxes: ["1.2.840.10008.1.2.1"]
        )
        
        let request = AssociateRequestPDU(
            calledAETitle: try AETitle("SCP"),
            callingAETitle: try AETitle("SCU"),
            presentationContexts: [context],
            implementationClassUID: "1.2.3.4.5"
        )
        
        let data = try request.encode()
        
        // PDU Type should be 0x01
        #expect(data[0] == 0x01)
        
        // Reserved byte should be 0x00
        #expect(data[1] == 0x00)
        
        // PDU Length (4 bytes, big endian)
        let pduLength = readUInt32BigEndian(from: data, at: 2)
        #expect(pduLength > 0)
        
        // Total length should match
        #expect(data.count == 6 + Int(pduLength))
    }
    
    @Test("Associate Request PDU with version name")
    func testAssociateRequestWithVersionName() throws {
        let context = try PresentationContext(
            id: 1,
            abstractSyntax: "1.2.840.10008.5.1.4.1.1.7",
            transferSyntaxes: ["1.2.840.10008.1.2.1"]
        )
        
        let request = AssociateRequestPDU(
            calledAETitle: try AETitle("SCP"),
            callingAETitle: try AETitle("SCU"),
            presentationContexts: [context],
            implementationClassUID: "1.2.3.4.5",
            implementationVersionName: "DICOMKIT_0_6"
        )
        
        #expect(request.implementationVersionName == "DICOMKIT_0_6")
        
        // Should encode without error
        let data = try request.encode()
        #expect(data.count > 0)
    }
    
    @Test("Associate Request round-trip encoding/decoding")
    func testAssociateRequestRoundTrip() throws {
        let context = try PresentationContext(
            id: 1,
            abstractSyntax: "1.2.840.10008.5.1.4.1.1.7",
            transferSyntaxes: ["1.2.840.10008.1.2.1"]
        )
        
        let original = AssociateRequestPDU(
            calledAETitle: try AETitle("PACS_SERVER"),
            callingAETitle: try AETitle("MY_CLIENT"),
            presentationContexts: [context],
            maxPDUSize: 32768,
            implementationClassUID: "1.2.3.4.5.6.7.8.9",
            implementationVersionName: "TEST_V1"
        )
        
        let encoded = try original.encode()
        let decoded = try PDUDecoder.decode(from: encoded)
        
        guard let decodedRequest = decoded as? AssociateRequestPDU else {
            #expect(Bool(false), "Decoded PDU is not AssociateRequestPDU")
            return
        }
        
        #expect(decodedRequest.calledAETitle == original.calledAETitle)
        #expect(decodedRequest.callingAETitle == original.callingAETitle)
        #expect(decodedRequest.presentationContexts.count == original.presentationContexts.count)
        #expect(decodedRequest.maxPDUSize == original.maxPDUSize)
        #expect(decodedRequest.implementationClassUID == original.implementationClassUID)
        #expect(decodedRequest.implementationVersionName == original.implementationVersionName)
    }
}

@Suite("Associate Accept PDU Tests")
struct AssociateAcceptPDUTests {
    
    @Test("Associate Accept PDU creation")
    func testAssociateAcceptCreation() throws {
        let accepted = AcceptedPresentationContext(
            id: 1,
            result: .acceptance,
            transferSyntax: "1.2.840.10008.1.2.1"
        )
        
        let accept = AssociateAcceptPDU(
            calledAETitle: try AETitle("MY_CLIENT"),
            callingAETitle: try AETitle("PACS_SERVER"),
            presentationContexts: [accepted],
            maxPDUSize: 16384,
            implementationClassUID: "1.2.3.4.5.6.7"
        )
        
        #expect(accept.pduType == .associateAccept)
        #expect(accept.presentationContexts.count == 1)
        #expect(accept.acceptedContextIDs.count == 1)
        #expect(accept.acceptedContextIDs[0] == 1)
    }
    
    @Test("Associate Accept PDU encoding")
    func testAssociateAcceptEncoding() throws {
        let accepted = AcceptedPresentationContext(
            id: 1,
            result: .acceptance,
            transferSyntax: "1.2.840.10008.1.2.1"
        )
        
        let accept = AssociateAcceptPDU(
            calledAETitle: try AETitle("SCU"),
            callingAETitle: try AETitle("SCP"),
            presentationContexts: [accepted],
            maxPDUSize: 16384,
            implementationClassUID: "1.2.3.4.5"
        )
        
        let data = try accept.encode()
        
        // PDU Type should be 0x02
        #expect(data[0] == 0x02)
        #expect(data.count > 6)
    }
    
    @Test("Associate Accept get accepted transfer syntax")
    func testAcceptedTransferSyntax() throws {
        let contexts = [
            AcceptedPresentationContext(id: 1, result: .acceptance, transferSyntax: "1.2.840.10008.1.2.1"),
            AcceptedPresentationContext(id: 3, result: .abstractSyntaxNotSupported, transferSyntax: nil)
        ]
        
        let accept = AssociateAcceptPDU(
            calledAETitle: try AETitle("SCU"),
            callingAETitle: try AETitle("SCP"),
            presentationContexts: contexts,
            maxPDUSize: 16384,
            implementationClassUID: "1.2.3.4.5"
        )
        
        #expect(accept.acceptedTransferSyntax(forContextID: 1) == "1.2.840.10008.1.2.1")
        #expect(accept.acceptedTransferSyntax(forContextID: 3) == nil)
        #expect(accept.acceptedTransferSyntax(forContextID: 5) == nil)
    }
    
    @Test("Associate Accept round-trip encoding/decoding")
    func testAssociateAcceptRoundTrip() throws {
        let contexts = [
            AcceptedPresentationContext(id: 1, result: .acceptance, transferSyntax: "1.2.840.10008.1.2.1"),
            AcceptedPresentationContext(id: 3, result: .abstractSyntaxNotSupported, transferSyntax: nil)
        ]
        
        let original = AssociateAcceptPDU(
            calledAETitle: try AETitle("SCU"),
            callingAETitle: try AETitle("SCP"),
            presentationContexts: contexts,
            maxPDUSize: 32768,
            implementationClassUID: "1.2.3.4.5.6",
            implementationVersionName: "TEST"
        )
        
        let encoded = try original.encode()
        let decoded = try PDUDecoder.decode(from: encoded)
        
        guard let decodedAccept = decoded as? AssociateAcceptPDU else {
            #expect(Bool(false), "Decoded PDU is not AssociateAcceptPDU")
            return
        }
        
        #expect(decodedAccept.calledAETitle == original.calledAETitle)
        #expect(decodedAccept.callingAETitle == original.callingAETitle)
        #expect(decodedAccept.presentationContexts.count == original.presentationContexts.count)
        #expect(decodedAccept.maxPDUSize == original.maxPDUSize)
    }
    
    @Test("Associate Accept decoding preserves rejected context result")
    func testAssociateAcceptDecodePreservesRejectedContextResult() throws {
        let contexts = [
            AcceptedPresentationContext(id: 1, result: .transferSyntaxesNotSupported, transferSyntax: nil)
        ]
        
        let original = AssociateAcceptPDU(
            calledAETitle: try AETitle("SCU"),
            callingAETitle: try AETitle("SCP"),
            presentationContexts: contexts,
            maxPDUSize: 16384,
            implementationClassUID: "1.2.3.4.5.6"
        )
        
        let encoded = try original.encode()
        let decoded = try PDUDecoder.decode(from: encoded)
        
        guard let decodedAccept = decoded as? AssociateAcceptPDU else {
            #expect(Bool(false), "Decoded PDU is not AssociateAcceptPDU")
            return
        }
        
        #expect(decodedAccept.presentationContexts.count == 1)
        #expect(decodedAccept.presentationContexts[0].result == .transferSyntaxesNotSupported)
        #expect(decodedAccept.acceptedContextIDs.isEmpty)
    }
}

@Suite("Associate Reject PDU Tests")
struct AssociateRejectPDUTests {
    
    @Test("Associate Reject PDU creation")
    func testAssociateRejectCreation() {
        let reject = AssociateRejectPDU(
            result: .rejectedPermanent,
            source: .serviceUser,
            reason: 3
        )
        
        #expect(reject.pduType == .associateReject)
        #expect(reject.result == .rejectedPermanent)
        #expect(reject.source == .serviceUser)
        #expect(reject.reason == 3)
    }
    
    @Test("Associate Reject PDU encoding")
    func testAssociateRejectEncoding() throws {
        let reject = AssociateRejectPDU(
            result: .rejectedPermanent,
            source: .serviceUser,
            reason: 7
        )
        
        let data = try reject.encode()
        
        // PDU Type should be 0x03
        #expect(data[0] == 0x03)
        
        // PDU Length should be 4
        let pduLength = readUInt32BigEndian(from: data, at: 2)
        #expect(pduLength == 4)
        
        // Total size should be 10 bytes
        #expect(data.count == 10)
    }
    
    @Test("Associate Reject reason descriptions")
    func testAssociateRejectReasonDescriptions() {
        // Service User reasons
        var reject = AssociateRejectPDU(result: .rejectedPermanent, source: .serviceUser, reason: 1)
        #expect(reject.reasonDescription.contains("No reason"))
        
        reject = AssociateRejectPDU(result: .rejectedPermanent, source: .serviceUser, reason: 3)
        #expect(reject.reasonDescription.contains("Calling AE title"))
        
        reject = AssociateRejectPDU(result: .rejectedPermanent, source: .serviceUser, reason: 7)
        #expect(reject.reasonDescription.contains("Called AE title"))
        
        // Service Provider (ACSE) reasons
        reject = AssociateRejectPDU(result: .rejectedTransient, source: .serviceProviderACSE, reason: 2)
        #expect(reject.reasonDescription.contains("Protocol version"))
        
        // Service Provider (Presentation) reasons
        reject = AssociateRejectPDU(result: .rejectedTransient, source: .serviceProviderPresentation, reason: 1)
        #expect(reject.reasonDescription.contains("congestion"))
    }
    
    @Test("Associate Reject round-trip encoding/decoding")
    func testAssociateRejectRoundTrip() throws {
        let original = AssociateRejectPDU(
            result: .rejectedPermanent,
            source: .serviceUser,
            reason: 7
        )
        
        let encoded = try original.encode()
        let decoded = try PDUDecoder.decode(from: encoded)
        
        guard let decodedReject = decoded as? AssociateRejectPDU else {
            #expect(Bool(false), "Decoded PDU is not AssociateRejectPDU")
            return
        }
        
        #expect(decodedReject.result == original.result)
        #expect(decodedReject.source == original.source)
        #expect(decodedReject.reason == original.reason)
    }
}

// MARK: - SCP/SCU Role Selection (PS3.7 D.3.3.4; PS3.4 C.4.3.1.1 / C.5.3)

@Suite("SCP/SCU Role Selection PDU Tests")
struct RoleSelectionPDUTests {

    private let ctImageStorage = "1.2.840.10008.5.1.4.1.1.2"
    private let mrImageStorage = "1.2.840.10008.5.1.4.1.1.4"
    private let studyRootGet = "1.2.840.10008.5.1.4.1.2.2.3"

    @Test("A-ASSOCIATE-RQ role selections round-trip through PDUDecoder")
    func testRequestRoleSelectionRoundTrip() throws {
        let contexts = [
            try PresentationContext(id: 1, abstractSyntax: studyRootGet, transferSyntaxes: ["1.2.840.10008.1.2.1"]),
            try PresentationContext(id: 3, abstractSyntax: ctImageStorage, transferSyntaxes: ["1.2.840.10008.1.2.1"]),
            try PresentationContext(id: 5, abstractSyntax: mrImageStorage, transferSyntaxes: ["1.2.840.10008.1.2.1"])
        ]
        let original = AssociateRequestPDU(
            calledAETitle: try AETitle("PACS"),
            callingAETitle: try AETitle("SCU"),
            presentationContexts: contexts,
            implementationClassUID: "1.2.3.4",
            roleSelections: [.both(ctImageStorage), .scpOnly(mrImageStorage)]
        )
        let encoded = try original.encode()
        let decoded = try PDUDecoder.decode(from: encoded)
        guard let request = decoded as? AssociateRequestPDU else {
            #expect(Bool(false), "Decoded PDU is not AssociateRequestPDU")
            return
        }
        #expect(request.roleSelections.count == 2)
        #expect(request.roleSelections[0] == .both(ctImageStorage))
        #expect(request.roleSelections[1] == .scpOnly(mrImageStorage))
        #expect(request.presentationContexts.count == 3)
    }

    @Test("A-ASSOCIATE-AC role selections round-trip through PDUDecoder")
    func testAcceptRoleSelectionRoundTrip() throws {
        let original = AssociateAcceptPDU(
            calledAETitle: try AETitle("PACS"),
            callingAETitle: try AETitle("SCU"),
            presentationContexts: [
                AcceptedPresentationContext(id: 1, result: .acceptance, transferSyntax: "1.2.840.10008.1.2.1"),
                AcceptedPresentationContext(id: 3, result: .acceptance, transferSyntax: "1.2.840.10008.1.2.1")
            ],
            maxPDUSize: 16384,
            implementationClassUID: "1.2.3.4",
            roleSelections: [
                SCPSCURoleSelection(sopClassUID: ctImageStorage, scuRole: false, scpRole: true),
                SCPSCURoleSelection(sopClassUID: mrImageStorage, scuRole: false, scpRole: false)
            ]
        )
        let encoded = try original.encode()
        let decoded = try PDUDecoder.decode(from: encoded)
        guard let accept = decoded as? AssociateAcceptPDU else {
            #expect(Bool(false), "Decoded PDU is not AssociateAcceptPDU")
            return
        }
        #expect(accept.roleSelections == original.roleSelections)
        #expect(accept.maxPDUSize == 16384)
    }

    @Test("Role selection sub-item encodes as type 0x54 with the PS3.7 D.3-9 layout")
    func testSubItemLayout() throws {
        let item = SCPSCURoleSelection.both("1.2.3").encode()
        #expect(item[0] == 0x54)
        #expect(item[1] == 0x00)
        #expect(Int(item[2]) << 8 | Int(item[3]) == 2 + 5 + 2)
        #expect(Int(item[4]) << 8 | Int(item[5]) == 5)
        #expect(item[item.count - 2] == 1)
        #expect(item[item.count - 1] == 1)
        let decoded = try SCPSCURoleSelection.decode(from: item.dropFirst(4))
        #expect(decoded == .both("1.2.3"))
    }

    @Test("NegotiatedRoles.resolve: no answer or unproposed class yields the default roles")
    func testResolveDefaults() {
        #expect(NegotiatedRoles.default == NegotiatedRoles(requestorIsSCU: true, requestorIsSCP: false))
        // No answer at all
        #expect(NegotiatedRoles.resolve(proposed: [.both(ctImageStorage)], accepted: [], sopClassUID: ctImageStorage) == .default)
        // Answer for a class that was never proposed
        #expect(NegotiatedRoles.resolve(proposed: [], accepted: [.both(ctImageStorage)], sopClassUID: ctImageStorage) == .default)
        // Answer may only reduce: proposed both, granted SCP only
        let reduced = NegotiatedRoles.resolve(
            proposed: [.both(ctImageStorage)],
            accepted: [SCPSCURoleSelection(sopClassUID: ctImageStorage, scuRole: false, scpRole: true)],
            sopClassUID: ctImageStorage)
        #expect(reduced == NegotiatedRoles(requestorIsSCU: false, requestorIsSCP: true))
        // Acceptor cannot grant more than proposed
        let capped = NegotiatedRoles.resolve(
            proposed: [.scpOnly(ctImageStorage)],
            accepted: [.both(ctImageStorage)],
            sopClassUID: ctImageStorage)
        #expect(capped == NegotiatedRoles(requestorIsSCU: false, requestorIsSCP: true))
    }

    @Test("NegotiatedAssociation exposes the SCP role per SOP Class")
    func testNegotiatedAssociationRoles() throws {
        let accept = AssociateAcceptPDU(
            calledAETitle: try AETitle("PACS"),
            callingAETitle: try AETitle("SCU"),
            presentationContexts: [AcceptedPresentationContext(id: 3, result: .acceptance, transferSyntax: "1.2.840.10008.1.2.1")],
            maxPDUSize: 16384,
            implementationClassUID: "1.2.3.4",
            roleSelections: [SCPSCURoleSelection(sopClassUID: ctImageStorage, scuRole: true, scpRole: true)]
        )
        let negotiated = NegotiatedAssociation(
            acceptPDU: accept, localMaxPDUSize: 16384,
            proposedRoleSelections: [.both(ctImageStorage), .both(mrImageStorage)])
        #expect(negotiated.isSCPRoleAccepted(for: ctImageStorage))
        #expect(!negotiated.isSCPRoleAccepted(for: mrImageStorage), "no answer means default roles (SCU only)")
    }
}
