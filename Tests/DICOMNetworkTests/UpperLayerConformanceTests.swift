import Foundation
import Testing
import XCTest
@testable import DICOMNetwork

// Tests that pin DICOM PS3.8 / PS3.7 2026a Upper Layer values:
// A-ASSOCIATE-AC rejected contexts (Table 9-18), A-ABORT source/reason
// (Tables 9-9, 9-26), A-ASSOCIATE-RJ reasons (Table 9-21), the state machine
// numbering (Tables 9-1..9-5, 9-10), Maximum Length semantics (Annex D.1),
// AE Title characters (Table 9-11), implementation sub-item limits
// (PS3.7 Table D.3-3/D.3-4), Protocol-version (Table 9-11) and the DIMSE
// statuses answered by the SCPs (PS3.7 §10.1).

// MARK: - Helpers

private let explicitVRLE = "1.2.840.10008.1.2.1"
private let verificationSOPClass = "1.2.840.10008.1.1"
private let scpTitle: AETitle = "SCP"
private let scuTitle: AETitle = "SCU"

private func readUInt16BE(_ data: Data, _ offset: Int) -> Int {
    Int(data[data.startIndex + offset]) << 8 | Int(data[data.startIndex + offset + 1])
}

private extension DICOMNetworkError {
    var isConnectionClosed: Bool {
        if case .connectionClosed = self { return true }
        return false
    }
}

// MARK: - 1. A-ASSOCIATE-AC rejected presentation contexts (PS3.8 Table 9-18)

@Suite("A-ASSOCIATE-AC rejected context sub-item")
struct AssociateAcceptRejectedContextTests {

    private func makeAccept(_ contexts: [AcceptedPresentationContext]) throws -> AssociateAcceptPDU {
        AssociateAcceptPDU(
            calledAETitle: scpTitle,
            callingAETitle: scuTitle,
            presentationContexts: contexts,
            maxPDUSize: 16384,
            implementationClassUID: "1.2.3.4"
        )
    }

    @Test("A rejected context still carries exactly one 0x40 Transfer Syntax sub-item (item-length 0)")
    func rejectedContextCarriesEmptyTransferSyntaxSubItem() throws {
        let accept = try makeAccept([
            AcceptedPresentationContext(id: 1, result: .abstractSyntaxNotSupported, transferSyntax: nil)
        ])
        let encoded = try accept.encode()

        // Locate the 0x21 item: after the 74-byte fixed part and the 0x10 item.
        var offset = 6 + 68
        #expect(encoded[offset] == 0x10)
        offset += 4 + readUInt16BE(encoded, offset + 2)
        #expect(encoded[offset] == 0x21)
        let itemLength = readUInt16BE(encoded, offset + 2)
        // ID, reserved, result, reserved + one 4-byte sub-item header with no name
        #expect(itemLength == 4 + 4)
        let subItemOffset = offset + 4 + 4
        #expect(encoded[subItemOffset] == 0x40)
        #expect(readUInt16BE(encoded, subItemOffset + 2) == 0)
        #expect(encoded[offset + 4 + 2] == PresentationContextResult.abstractSyntaxNotSupported.rawValue)
    }

    @Test("Decoding a rejected context yields transferSyntax nil and isAccepted false")
    func rejectedContextRoundTrip() throws {
        let accept = try makeAccept([
            AcceptedPresentationContext(id: 1, result: .acceptance, transferSyntax: explicitVRLE),
            AcceptedPresentationContext(id: 3, result: .transferSyntaxesNotSupported, transferSyntax: nil)
        ])
        let decoded = try #require(try PDUDecoder.decode(from: try accept.encode()) as? AssociateAcceptPDU)
        #expect(decoded.presentationContexts.count == 2)
        #expect(decoded.presentationContexts[0].isAccepted)
        #expect(decoded.presentationContexts[0].transferSyntax == explicitVRLE)
        #expect(decoded.presentationContexts[1].result == .transferSyntaxesNotSupported)
        #expect(decoded.presentationContexts[1].transferSyntax == nil)
        #expect(decoded.presentationContexts[1].isAccepted == false)
        #expect(decoded.acceptedContextIDs == [1])
    }

    @Test("A rejected context whose sub-item names a syntax is not tested: transferSyntax stays nil")
    func rejectedContextWithNamedSyntaxIsNotSignificant() throws {
        let accept = try makeAccept([
            AcceptedPresentationContext(id: 5, result: .abstractSyntaxNotSupported, transferSyntax: explicitVRLE)
        ])
        let decoded = try #require(try PDUDecoder.decode(from: try accept.encode()) as? AssociateAcceptPDU)
        #expect(decoded.presentationContexts[0].transferSyntax == nil)
        #expect(decoded.presentationContexts[0].isAccepted == false)
    }
}

// MARK: - 2. A-ABORT source and reason (PS3.8 Tables 9-9, 9-26)

@Suite("A-ABORT service-user reason")
struct AbortReasonEncodingTests {

    @Test("A service-user abort is sent with reason 00H whatever reason was given")
    func serviceUserAbortEncodesReasonZero() throws {
        let abort = AbortPDU(source: .serviceUser, reason: AbortReason.unexpectedPDU)
        let encoded = try abort.encode()
        #expect(encoded.count == 10)
        #expect(encoded[8] == 0)   // Source: service-user
        #expect(encoded[9] == 0)   // Reason: not significant, sent as 00H
    }

    @Test("A service-provider abort keeps its reason")
    func serviceProviderAbortKeepsReason() throws {
        let encoded = try AbortPDU(source: .serviceProvider, reason: .unexpectedPDU).encode()
        #expect(encoded[8] == 2)
        #expect(encoded[9] == AbortReason.unexpectedPDU.rawValue)
    }
}

// MARK: - 3. A-ASSOCIATE-RJ reasons (PS3.8 Table 9-21)

@Suite("A-ASSOCIATE-RJ reason table")
struct AssociateRejectReasonTableTests {

    @Test("Console formatter and PDU share one reason table: 3 = calling, 7 = called")
    func consoleFormatterUsesPDUTable() {
        for (source, reason) in [
            (AssociateRejectSource.serviceUser, UInt8(1)), (.serviceUser, 2), (.serviceUser, 3), (.serviceUser, 7),
            (.serviceProviderACSE, 1), (.serviceProviderACSE, 2),
            (.serviceProviderPresentation, 0), (.serviceProviderPresentation, 1), (.serviceProviderPresentation, 2)
        ] {
            let expected = AssociateRejectPDU(result: .rejectedPermanent, source: source, reason: reason).reasonDescription
            #expect(NetworkConsole.associateRejectReasonDescription(source: source, reason: reason) == expected)
        }
        #expect(NetworkConsole.associateRejectReasonDescription(source: .serviceUser, reason: 3)
                    .lowercased().contains("calling ae"))
        #expect(NetworkConsole.associateRejectReasonDescription(source: .serviceUser, reason: 7)
                    .lowercased().contains("called ae"))
        // Source 3 reason 0 is reserved, not "no reason given"
        #expect(NetworkConsole.associateRejectReasonDescription(source: .serviceProviderPresentation, reason: 0)
                    .lowercased().contains("unknown"))
    }

    @Test("C-ECHO hints name the Calling AE for reason 3 and the Called AE for reason 7")
    func echoHintsMatchTable921() {
        let calling = NetworkConsole.echoFailureDetail(
            .associationRejected(result: .rejectedPermanent, source: .serviceUser, reason: 3),
            host: "h", port: 104, callingAE: "MY_CALLING", calledAE: "MY_CALLED", timeout: 5)
        #expect(calling.contains("Calling AE Title"))
        #expect(calling.contains("MY_CALLING"))
        #expect(!calling.contains("\"MY_CALLED\""))

        let called = NetworkConsole.echoFailureDetail(
            .associationRejected(result: .rejectedPermanent, source: .serviceUser, reason: 7),
            host: "h", port: 104, callingAE: "MY_CALLING", calledAE: "MY_CALLED", timeout: 5)
        #expect(called.contains("Called AE Title"))
        #expect(called.contains("MY_CALLED"))
        #expect(!called.contains("\"MY_CALLING\""))

        let version = NetworkConsole.echoFailureDetail(
            .associationRejected(result: .rejectedPermanent, source: .serviceProviderACSE, reason: 2),
            host: "h", port: 104, callingAE: "A", calledAE: "B", timeout: 5)
        #expect(version.contains("Protocol-version"))
        #expect(!version.lowercased().contains("transfer syntax"))
    }
}

// MARK: - 5. State numbering and Sta13 transitions (PS3.8 Tables 9-1..9-5, 9-10)

@Suite("Upper Layer state numbering")
struct UpperLayerStateNumberingTests {

    @Test("State descriptions carry the PS3.8 Sta numbers")
    func stateDescriptions() {
        #expect(AssociationState.idle.description.hasSuffix("(Sta1)"))
        #expect(AssociationState.awaitingLocalAssociateResponse.description.hasSuffix("(Sta2/Sta3)"))
        #expect(AssociationState.awaitingTransportOpen.description.hasSuffix("(Sta4)"))
        #expect(AssociationState.awaitingRemoteAssociateResponse.description.hasSuffix("(Sta5)"))
        #expect(AssociationState.established.description.hasSuffix("(Sta6)"))
        #expect(AssociationState.awaitingRemoteReleaseResponse.description.hasSuffix("(Sta7)"))
        #expect(AssociationState.awaitingLocalReleaseResponse.description.hasSuffix("(Sta8)"))
        #expect(AssociationState.releaseCollision.description.hasSuffix("(Sta9-12)"))
        #expect(AssociationState.awaitingTransportClose.description.hasSuffix("(Sta13)"))
    }

    @Test("Sta13 + A-ABORT PDU → AA-2 → Sta1 with the transport closed")
    func sta13AbortReceived() {
        let machine = AssociationStateMachine(initialState: .awaitingTransportClose)
        let result = machine.handleEvent(.abortReceived(AbortPDU(source: .serviceUser, reason: 0)))
        #expect(result.newState == .idle)
        #expect(machine.state == .idle)
        #expect(result.actions.contains { if case .closeTransport = $0 { return true } else { return false } })
    }

    @Test("Sta13 + ARTIM expiry → AA-2 → Sta1 with the transport closed")
    func sta13ARTIMExpired() {
        let machine = AssociationStateMachine(initialState: .awaitingTransportClose)
        let result = machine.handleEvent(.artimTimerExpired)
        #expect(result.newState == .idle)
        #expect(result.actions.contains { if case .closeTransport = $0 { return true } else { return false } })
    }

    @Test("A local timeout in Sta5/Sta7 emits an AA-1 abort: service-user source, reason 0")
    func localTimeoutAbortIsServiceUser() {
        for state in [AssociationState.awaitingRemoteAssociateResponse, .awaitingRemoteReleaseResponse] {
            let machine = AssociationStateMachine(initialState: state)
            let result = machine.handleEvent(.artimTimerExpired)
            #expect(result.newState == .awaitingTransportClose)
            var sent: AbortPDU?
            for action in result.actions {
                if case .sendAbort(let pdu) = action { sent = pdu }
            }
            #expect(sent?.source == .serviceUser)
            #expect(sent?.reason == 0)
        }
    }
}

// MARK: - 6. Maximum Length (PS3.8 Annex D.1)

@Suite("Maximum Length semantics")
struct MaximumLengthTests {

    @Test("A peer Maximum Length of 0 means unlimited: the local value is used")
    func zeroFromPeerMeansUnlimited() throws {
        #expect(negotiatedMaxPDUSize(local: 65536, remote: 0) == 65536)
        #expect(negotiatedMaxPDUSize(local: 0, remote: 32768) == 32768)
        #expect(negotiatedMaxPDUSize(local: 65536, remote: 16384) == 16384)
        #expect(negotiatedMaxPDUSize(local: 0, remote: 0) == 0)

        let accept = AssociateAcceptPDU(
            calledAETitle: scpTitle, callingAETitle: scuTitle,
            presentationContexts: [AcceptedPresentationContext(id: 1, result: .acceptance, transferSyntax: explicitVRLE)],
            maxPDUSize: 0, implementationClassUID: "1.2.3")
        let negotiated = NegotiatedAssociation(acceptPDU: accept, localMaxPDUSize: 65536)
        #expect(negotiated.maxPDUSize == 65536)
    }

    @Test("The limit governs P-DATA-TF only, and a local limit of 0 disables it")
    func lengthCheckAppliesToDataTransferOnly() {
        #expect(throws: DICOMNetworkError.self) {
            try checkPDULength(type: .dataTransfer, length: 16385, maxPDUSize: 16384)
        }
        #expect(throws: Never.self) { try checkPDULength(type: .dataTransfer, length: 16384, maxPDUSize: 16384) }
        #expect(throws: Never.self) { try checkPDULength(type: .associateRequest, length: 1_000_000, maxPDUSize: 16384) }
        #expect(throws: Never.self) { try checkPDULength(type: .associateAccept, length: 1_000_000, maxPDUSize: 16384) }
        #expect(throws: Never.self) { try checkPDULength(type: .dataTransfer, length: 10_000_000, maxPDUSize: 0) }
    }

    @Test("A PDV carries maxPDUSize - 6 bytes of data (PS3.8 Table 9-22/9-23)")
    func fragmentSizeIsMaxPDUSizeMinusSix() throws {
        let fragmenter = MessageFragmenter(maxPDUSize: 100)
        #expect(fragmenter.maxPDVDataSize == 94)

        let dataSet = Data(repeating: 0xAB, count: 94 * 2 + 1)
        let pdvs = fragmenter.fragmentDataSet(dataSet, presentationContextID: 1)
        #expect(pdvs.count == 3)
        #expect(pdvs[0].data.count == 94)
        #expect(pdvs[1].data.count == 94)
        #expect(pdvs[2].data.count == 1)

        // The encoded P-DATA-TF declares exactly maxPDUSize in its length field
        let pdu = try DataTransferPDU(pdv: pdvs[0]).encode()
        let (_, declaredLength) = try PDUDecoder.readHeader(from: pdu)
        #expect(declaredLength == 100)
        #expect(pdu.count == 106)
    }

    @Test("Maximum Length 0 fragments to the implementation default")
    func zeroMaxPDUSizeUsesDefault() {
        #expect(MessageFragmenter(maxPDUSize: 0).maxPDVDataSize == defaultMaxPDUSize - 6)
        #expect(MessageFragmenter(maxPDUSize: 6).maxPDVDataSize == defaultMaxPDUSize - 6)
    }
}

// MARK: - 7. AE Title characters (PS3.8 Table 9-11; PS3.5 Table 6.2-1)

@Suite("AE Title character set")
struct AETitleCharacterSetTests {

    @Test("Only SPACE (20H) padding is trimmed")
    func onlySpaceIsTrimmed() throws {
        #expect(try AETitle("  PACS  ").value == "PACS")
        #expect(try AETitle("MY PACS").value == "MY PACS")
        let tabPadded = "\tPACS"
        #expect(throws: DICOMNetworkError.self) { _ = try AETitle(tabPadded) }
    }

    @Test("Control characters, DEL and backslash are rejected; 20H-7EH otherwise allowed")
    func g0SetWithoutBackslash() throws {
        for bad in ["PA\u{00}CS", "PA\u{1B}CS", "PA\u{7F}CS", "PA\\CS", "PA\rCS", "PAÇS"] {
            #expect(throws: DICOMNetworkError.self, "\(bad.unicodeScalars.map { $0.value })") { _ = try AETitle(bad) }
        }
        #expect(try AETitle("!#$%&'()*+,-./:").value == "!#$%&'()*+,-./:")
        #expect(try AETitle(";<=>?@[]^_`{|}~").value == ";<=>?@[]^_`{|}~")
    }

    @Test("NUL padding is accepted on decode")
    func nulPaddingOnDecode() throws {
        var bytes = Array("STORESCP".utf8)
        bytes.append(contentsOf: [UInt8](repeating: 0x00, count: 16 - bytes.count))
        let title = try #require(AETitle.from(data: Data(bytes)))
        #expect(title.value == "STORESCP")
        #expect(title.data == Data("STORESCP        ".utf8))
    }

    @Test("Length is counted in bytes: 16 allowed, 17 rejected")
    func sixteenBytes() throws {
        #expect(try AETitle("ABCDEFGHIJKLMNOP").value.count == 16)
        let seventeen = "ABCDEFGHIJKLMNOPQ"
        #expect(throws: DICOMNetworkError.self) { _ = try AETitle(seventeen) }
    }
}

// MARK: - 8. Implementation sub-item limits (PS3.7 Table D.3-3/D.3-4; PS3.5 UI)

@Suite("Implementation sub-item limits")
struct ImplementationSubItemLimitTests {

    private func request(classUID: String, versionName: String?) throws -> AssociateRequestPDU {
        AssociateRequestPDU(
            calledAETitle: scpTitle, callingAETitle: scuTitle,
            presentationContexts: [try PresentationContext(id: 1, abstractSyntax: verificationSOPClass, transferSyntaxes: [explicitVRLE])],
            implementationClassUID: classUID, implementationVersionName: versionName)
    }

    private func accept(classUID: String, versionName: String?) throws -> AssociateAcceptPDU {
        AssociateAcceptPDU(
            calledAETitle: scpTitle, callingAETitle: scuTitle,
            presentationContexts: [AcceptedPresentationContext(id: 1, result: .acceptance, transferSyntax: explicitVRLE)],
            maxPDUSize: 16384, implementationClassUID: classUID, implementationVersionName: versionName)
    }

    @Test("An Implementation Class UID of 64 bytes encodes; 65 bytes fails")
    func classUIDLimit() throws {
        let sixtyFour = "1." + String(repeating: "2", count: 62)
        #expect(sixtyFour.utf8.count == 64)
        #expect(throws: Never.self) { _ = try request(classUID: sixtyFour, versionName: nil).encode() }
        #expect(throws: DICOMNetworkError.self) { _ = try request(classUID: sixtyFour + "3", versionName: nil).encode() }
        #expect(throws: DICOMNetworkError.self) { _ = try accept(classUID: sixtyFour + "3", versionName: nil).encode() }
    }

    @Test("An Implementation Version Name of 1-16 characters encodes; empty or 17 fails")
    func versionNameLimit() throws {
        #expect(throws: Never.self) { _ = try request(classUID: "1.2.3", versionName: "A").encode() }
        #expect(throws: Never.self) { _ = try request(classUID: "1.2.3", versionName: String(repeating: "V", count: 16)).encode() }
        #expect(throws: Never.self) { _ = try request(classUID: "1.2.3", versionName: nil).encode() }
        #expect(throws: DICOMNetworkError.self) { _ = try request(classUID: "1.2.3", versionName: "").encode() }
        #expect(throws: DICOMNetworkError.self) { _ = try request(classUID: "1.2.3", versionName: String(repeating: "V", count: 17)).encode() }
        #expect(throws: DICOMNetworkError.self) { _ = try accept(classUID: "1.2.3", versionName: "").encode() }
        #expect(throws: DICOMNetworkError.self) { _ = try accept(classUID: "1.2.3", versionName: String(repeating: "V", count: 17)).encode() }
    }
}

// MARK: - 9. Protocol-version (PS3.8 Table 9-11)

@Suite("Protocol-version decoding")
struct ProtocolVersionDecodingTests {

    @Test("The decoder preserves the peer's Protocol-version and only bit 0 is tested")
    func decoderKeepsProtocolVersion() throws {
        let context = try PresentationContext(id: 1, abstractSyntax: verificationSOPClass, transferSyntaxes: [explicitVRLE])
        for (version, supported) in [(UInt16(1), true), (0x0003, true), (0x0002, false), (0x0000, false)] {
            let request = AssociateRequestPDU(
                protocolVersion: version,
                calledAETitle: scpTitle, callingAETitle: scuTitle,
                presentationContexts: [context], implementationClassUID: "1.2.3")
            let encoded = try request.encode()
            #expect(readUInt16BE(encoded, 6) == Int(version))
            let decoded = try #require(try PDUDecoder.decode(from: encoded) as? AssociateRequestPDU)
            #expect(decoded.protocolVersion == version)
            #expect(decoded.isProtocolVersionSupported == supported)
        }
        // The public initializer always sends version 1
        let local = AssociateRequestPDU(
            calledAETitle: scpTitle, callingAETitle: scuTitle,
            presentationContexts: [context], implementationClassUID: "1.2.3")
        #expect(local.protocolVersion == 1)
    }
}

#if canImport(Network)

// MARK: - 2/4. Association behaviour on a scripted transport

/// A deterministic transport: `enqueue` bytes the peer "sends", `sentData`
/// records what the association sent. A receive that cannot be served is held
/// until bytes arrive or the transport is cancelled.
private final class ScriptedTransport: DICOMConnectionTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var stateHandler: (@Sendable (DICOMConnectionTransportState) -> Void)?
    private var inbound = Data()
    private var pendingReceive: (length: Int, completion: @Sendable (Data?, Bool, String?) -> Void)?
    private var closedByPeer = false
    private(set) var sends: [Data] = []

    var sentData: [Data] {
        lock.lock(); defer { lock.unlock() }
        return sends
    }

    func sentPDUs() throws -> [any PDU] {
        try sentData.map { try PDUDecoder.decode(from: $0) }
    }

    func enqueue(_ pdu: any PDU) throws {
        enqueue(try pdu.encode())
    }

    func enqueue(_ data: Data) {
        lock.lock()
        inbound.append(data)
        lock.unlock()
        servePending()
    }

    /// The peer closed its side: pending and future receives complete as closed.
    func closeFromPeer() {
        lock.lock()
        closedByPeer = true
        lock.unlock()
        servePending()
    }

    private func servePending() {
        lock.lock()
        guard let pending = pendingReceive else { lock.unlock(); return }
        if inbound.count >= pending.length {
            let chunk = inbound.prefix(pending.length)
            inbound.removeFirst(pending.length)
            pendingReceive = nil
            lock.unlock()
            pending.completion(Data(chunk), false, nil)
        } else if closedByPeer {
            pendingReceive = nil
            lock.unlock()
            pending.completion(nil, true, nil)
        } else {
            lock.unlock()
        }
    }

    // DICOMConnectionTransport

    func setStateUpdateHandler(_ handler: (@Sendable (DICOMConnectionTransportState) -> Void)?) {
        lock.lock(); stateHandler = handler; lock.unlock()
    }

    func start() {
        lock.lock(); let handler = stateHandler; lock.unlock()
        handler?(.ready)
    }

    func send(content: Data, completion: @escaping @Sendable (String?) -> Void) {
        lock.lock(); sends.append(content); lock.unlock()
        completion(nil)
    }

    func receive(minimumIncompleteLength: Int, maximumLength: Int,
                 completion: @escaping @Sendable (Data?, Bool, String?) -> Void) {
        lock.lock()
        pendingReceive = (maximumLength, completion)
        lock.unlock()
        servePending()
    }

    func cancel() {
        lock.lock()
        let handler = stateHandler
        let pending = pendingReceive
        pendingReceive = nil
        lock.unlock()
        pending?.completion(nil, true, "cancelled")
        handler?(.cancelled)
    }

    func forceCancel() { cancel() }
}

@Suite("Association Upper Layer behaviour", .serialized)
struct AssociationUpperLayerTests {

    private func makeAssociation(transport: ScriptedTransport, artim: TimeInterval? = 5) throws -> Association {
        let configuration = AssociationConfiguration(
            callingAETitle: scuTitle, calledAETitle: scpTitle,
            host: "scripted.test", port: 104, implementationClassUID: "1.2.826.0.1.3680043.10.543.99",
            timeout: 5, artimTimeout: artim, tlsConfiguration: nil)
        return Association(configuration: configuration) { configuration in
            DICOMConnection(host: configuration.host, port: configuration.port,
                            maxPDUSize: configuration.maxPDUSize, timeout: configuration.timeout,
                            tlsConfiguration: nil, transport: transport)
        }
    }

    private func acceptPDU() throws -> AssociateAcceptPDU {
        AssociateAcceptPDU(
            calledAETitle: scpTitle, callingAETitle: scuTitle,
            presentationContexts: [AcceptedPresentationContext(id: 1, result: .acceptance, transferSyntax: explicitVRLE)],
            maxPDUSize: 16384, implementationClassUID: "1.2.3")
    }

    private func establish(_ association: Association, _ transport: ScriptedTransport) async throws {
        try transport.enqueue(try acceptPDU())
        let context = try PresentationContext(id: 1, abstractSyntax: verificationSOPClass, transferSyntaxes: [explicitVRLE])
        _ = try await association.request(presentationContexts: [context])
        #expect(association.state == .established)
    }

    @Test("Sta6 + A-RELEASE-RQ: the association answers A-RELEASE-RP (AR-2, AR-4), closes and returns to Sta1")
    func receiveAnswersReleaseRequest() async throws {
        let transport = ScriptedTransport()
        let association = try makeAssociation(transport: transport)
        try await establish(association, transport)

        try transport.enqueue(ReleaseRequestPDU())
        let closed = await #expect(throws: DICOMNetworkError.self) {
            _ = try await association.receive()
        }
        #expect(closed?.isConnectionClosed == true)
        let sent = try transport.sentPDUs()
        #expect(sent.count == 2)
        #expect(sent.last is ReleaseResponsePDU)
        #expect(association.state == .idle)
    }

    @Test("Release collision: after A-RELEASE-RP is sent the requestor waits for the peer's A-RELEASE-RP (AR-8, AR-9, AR-3)")
    func releaseCollisionWaitsForPeerReleaseResponse() async throws {
        let transport = ScriptedTransport()
        let association = try makeAssociation(transport: transport)
        try await establish(association, transport)

        // Peer's A-RELEASE-RQ crosses ours; its A-RELEASE-RP follows only after ours
        try transport.enqueue(ReleaseRequestPDU())
        let release = Task { try await association.release() }
        try await Task.sleep(for: .milliseconds(100))
        var sent = try transport.sentPDUs()
        #expect(sent.count == 3)
        #expect(sent[1] is ReleaseRequestPDU)
        #expect(sent[2] is ReleaseResponsePDU)
        #expect(association.state == .awaitingRemoteReleaseResponse)  // Sta11

        try transport.enqueue(ReleaseResponsePDU())
        try await release.value
        sent = try transport.sentPDUs()
        #expect(sent.count == 3)
        #expect(association.state == .idle)
    }

    @Test("Release collision without the peer's A-RELEASE-RP times out: AA-1 abort with service-user source, reason 0")
    func releaseCollisionTimeoutAborts() async throws {
        let transport = ScriptedTransport()
        let association = try makeAssociation(transport: transport, artim: 0.2)
        try await establish(association, transport)

        try transport.enqueue(ReleaseRequestPDU())
        let expired = await #expect(throws: DICOMNetworkError.self) {
            try await association.release()
        }
        #expect(expired?.isARTIMExpired == true)
        let sent = try transport.sentPDUs()
        let abort = try #require(sent.last as? AbortPDU)
        #expect(abort.source == .serviceUser)
        #expect(abort.reason == 0)
        #expect(association.state == .idle)
    }

    @Test("P-DATA-TF during the release wait is discarded (AR-6) and A-RELEASE-RP completes the release")
    func dataDuringReleaseIsDiscarded() async throws {
        let transport = ScriptedTransport()
        let association = try makeAssociation(transport: transport)
        try await establish(association, transport)

        let pdv = PresentationDataValue(presentationContextID: 1, isCommand: true, isLastFragment: true, data: Data([0, 0]))
        try transport.enqueue(DataTransferPDU(pdv: pdv))
        try transport.enqueue(ReleaseResponsePDU())
        try await association.release()
        #expect(association.state == .idle)
        let sent = try transport.sentPDUs()
        #expect(sent.count == 2)
        #expect(sent.last is ReleaseRequestPDU)
    }

    @Test("ARTIM expiry while awaiting A-ASSOCIATE-AC sends an AA-1 abort: service-user source, reason 0")
    func artimExpiryDuringRequestSendsServiceUserAbort() async throws {
        let transport = ScriptedTransport()
        let association = try makeAssociation(transport: transport, artim: 0.2)
        let context = try PresentationContext(id: 1, abstractSyntax: verificationSOPClass, transferSyntaxes: [explicitVRLE])
        let expired = await #expect(throws: DICOMNetworkError.self) {
            _ = try await association.request(presentationContexts: [context])
        }
        #expect(expired?.isARTIMExpired == true)
        let sent = try transport.sentPDUs()
        #expect(sent.count == 2)
        #expect(sent[0] is AssociateRequestPDU)
        let abort = try #require(sent[1] as? AbortPDU)
        #expect(abort.source == .serviceUser)
        #expect(abort.reason == 0)
        #expect(try abort.encode()[9] == 0)
        #expect(association.state == .idle)
    }

    @Test("abort() sends a service-user abort; a protocol reason is sent as service-provider (AA-8)")
    func abortSourceFollowsReason() async throws {
        let transport = ScriptedTransport()
        let association = try makeAssociation(transport: transport)
        try await establish(association, transport)
        try await association.abort()
        var abort = try #require(try transport.sentPDUs().last as? AbortPDU)
        #expect(abort.source == .serviceUser)
        #expect(abort.reason == 0)

        let transport2 = ScriptedTransport()
        let association2 = try makeAssociation(transport: transport2)
        try await establish(association2, transport2)
        try await association2.abort(reason: .unexpectedPDU)
        abort = try #require(try transport2.sentPDUs().last as? AbortPDU)
        #expect(abort.source == .serviceProvider)
        #expect(abort.reason == AbortReason.unexpectedPDU.rawValue)
    }

    @Test("An unexpected PDU in Sta6 is answered with a service-provider abort, reason unexpected PDU")
    func unexpectedPDUAbortsAsServiceProvider() async throws {
        let transport = ScriptedTransport()
        let association = try makeAssociation(transport: transport)
        try await establish(association, transport)
        try transport.enqueue(try acceptPDU())
        await #expect(throws: DICOMNetworkError.self) {
            _ = try await association.receive()
        }
        let abort = try #require(try transport.sentPDUs().last as? AbortPDU)
        #expect(abort.source == .serviceProvider)
        #expect(abort.reason == AbortReason.unexpectedPDU.rawValue)
    }
}

// MARK: - 3/9/11/12/13. SCP behaviour over loopback

/// Drives the SCPs over a real loopback socket with raw PDUs.
final class SCPConformanceLoopbackTests: XCTestCase {

    private static let scpAE = "UL_SCP"
    private static let scuAE = "UL_SCU"

    private func connect(port: UInt16) async throws -> DICOMConnection {
        let connection = try DICOMConnection(host: "127.0.0.1", port: port, maxPDUSize: 16384, timeout: 5, tlsConfiguration: nil)
        try await connection.connect()
        return connection
    }

    private func associateRequest(sopClass: String, protocolVersion: UInt16 = 1, contextID: UInt8 = 1) throws -> AssociateRequestPDU {
        AssociateRequestPDU(
            protocolVersion: protocolVersion,
            calledAETitle: try AETitle(Self.scpAE), callingAETitle: try AETitle(Self.scuAE),
            presentationContexts: [try PresentationContext(id: contextID, abstractSyntax: sopClass, transferSyntaxes: [explicitVRLE])],
            maxPDUSize: 16384, implementationClassUID: "1.2.826.0.1.3680043.10.543.99")
    }

    /// Establishes an association and returns the connection, or the A-ASSOCIATE-RJ.
    private func associate(port: UInt16, sopClass: String, protocolVersion: UInt16 = 1) async throws -> (DICOMConnection, any PDU) {
        let connection = try await connect(port: port)
        try await connection.send(pdu: try associateRequest(sopClass: sopClass, protocolVersion: protocolVersion))
        let response = try await connection.receivePDU()
        return (connection, response)
    }

    private func exchange(_ connection: DICOMConnection, command: CommandSet, contextID: UInt8 = 1) async throws -> CommandSet {
        let pdv = PresentationDataValue(presentationContextID: contextID, isCommand: true, isLastFragment: true, data: command.encode())
        try await connection.send(pdu: DataTransferPDU(pdv: pdv))
        let assembler = MessageAssembler()
        while true {
            let pdu = try await connection.receivePDU()
            let data = try XCTUnwrap(pdu as? DataTransferPDU, "Expected P-DATA-TF, got \(pdu.pduType)")
            if let message = try assembler.addPDVs(from: data) {
                return message.commandSet
            }
        }
    }

    private func release(_ connection: DICOMConnection) async {
        try? await connection.send(pdu: ReleaseRequestPDU())
        _ = try? await connection.receivePDU()
        await connection.disconnect()
    }

    // 9. Protocol-version bit 0 clear → A-ASSOCIATE-RJ permanent, ACSE, reason 2

    func testStorageSCPRejectsProtocolVersionWithoutBit0() async throws {
        let port: UInt16 = 19171
        let server = DICOMStorageServer(
            configuration: StorageSCPConfiguration(aeTitle: try AETitle(Self.scpAE), port: port),
            delegate: DefaultStorageHandler(storageDirectory: FileManager.default.temporaryDirectory))
        try await server.start()
        defer { Task { await server.stop() } }
        try await Task.sleep(for: .milliseconds(200))

        let (connection, response) = try await associate(port: port, sopClass: verificationSOPClass, protocolVersion: 0x0002)
        let reject = try XCTUnwrap(response as? AssociateRejectPDU, "Expected A-ASSOCIATE-RJ, got \(response.pduType)")
        XCTAssertEqual(reject.result, .rejectedPermanent)
        XCTAssertEqual(reject.source, .serviceProviderACSE)
        XCTAssertEqual(reject.reason, 2)
        await connection.disconnect()
        await server.stop()
    }

    // 13. Unsupported DIMSE request → matching response with status 0211H

    func testStorageSCPAnswersUnsupportedOperationWith0211() async throws {
        let port: UInt16 = 19172
        let server = DICOMStorageServer(
            configuration: StorageSCPConfiguration(aeTitle: try AETitle(Self.scpAE), port: port),
            delegate: DefaultStorageHandler(storageDirectory: FileManager.default.temporaryDirectory))
        try await server.start()
        defer { Task { await server.stop() } }
        try await Task.sleep(for: .milliseconds(200))

        let (connection, response) = try await associate(port: port, sopClass: verificationSOPClass)
        XCTAssertTrue(response is AssociateAcceptPDU, "Expected A-ASSOCIATE-AC, got \(response.pduType)")

        var nGet = CommandSet()
        nGet.setCommand(.nGetRequest)
        nGet.setMessageID(7)
        nGet.setRequestedSOPClassUID(verificationSOPClass)
        nGet.setRequestedSOPInstanceUID("1.2.3.4")
        nGet.setHasDataSet(false)

        let reply = try await exchange(connection, command: nGet)
        XCTAssertEqual(reply.command, .nGetResponse)
        XCTAssertEqual(reply.messageIDBeingRespondedTo, 7)
        XCTAssertEqual(reply.status?.rawValue, 0x0211)
        XCTAssertFalse(reply.hasDataSet)

        await release(connection)
        await server.stop()
    }

    // 3. Storage SCP rejects an unknown Calling AE with source 1, reason 3

    func testStorageSCPRejectsUnknownCallingAEWithReason3() async throws {
        let port: UInt16 = 19173
        let server = DICOMStorageServer(
            configuration: StorageSCPConfiguration(aeTitle: try AETitle(Self.scpAE), port: port, callingAEWhitelist: ["SOMEONE_ELSE"]),
            delegate: DefaultStorageHandler(storageDirectory: FileManager.default.temporaryDirectory))
        try await server.start()
        defer { Task { await server.stop() } }
        try await Task.sleep(for: .milliseconds(200))

        let (connection, response) = try await associate(port: port, sopClass: verificationSOPClass)
        let reject = try XCTUnwrap(response as? AssociateRejectPDU, "Expected A-ASSOCIATE-RJ, got \(response.pduType)")
        XCTAssertEqual(reject.result, .rejectedPermanent)
        XCTAssertEqual(reject.source, .serviceUser)
        XCTAssertEqual(reject.reason, 3)
        await connection.disconnect()
        await server.stop()
    }

    // 3. Storage Commitment SCP: no acceptable context → (permanent, service-user, reason 1)

    func testCommitmentSCPRejectsWithNoAcceptableContextAsServiceUserReason1() async throws {
        let port: UInt16 = 19174
        let server = StorageCommitmentServer(
            configuration: StorageCommitmentSCPConfiguration(aeTitle: try AETitle(Self.scpAE), port: port),
            delegate: DefaultCommitmentHandler())
        try await server.start()
        defer { Task { await server.stop() } }
        try await Task.sleep(for: .milliseconds(200))

        let (connection, response) = try await associate(port: port, sopClass: verificationSOPClass)
        let reject = try XCTUnwrap(response as? AssociateRejectPDU, "Expected A-ASSOCIATE-RJ, got \(response.pduType)")
        XCTAssertEqual(reject.result, .rejectedPermanent)
        XCTAssertEqual(reject.source, .serviceUser)
        XCTAssertEqual(reject.reason, 1)
        await connection.disconnect()
        await server.stop()
    }

    // 12. N-ACTION statuses (PS3.7 §10.1.4.1.10)

    func testCommitmentSCPAnswersNoSuchActionAndNoSuchSOPClass() async throws {
        let port: UInt16 = 19175
        let server = StorageCommitmentServer(
            configuration: StorageCommitmentSCPConfiguration(aeTitle: try AETitle(Self.scpAE), port: port),
            delegate: DefaultCommitmentHandler())
        try await server.start()
        defer { Task { await server.stop() } }
        try await Task.sleep(for: .milliseconds(200))

        let (connection, response) = try await associate(port: port, sopClass: storageCommitmentPushModelSOPClassUID)
        XCTAssertTrue(response is AssociateAcceptPDU, "Expected A-ASSOCIATE-AC, got \(response.pduType)")

        // PS3.7 §10.1.4.1.10: No such Action (0123H)
        let wrongAction = NActionRequest(
            messageID: 1, requestedSOPClassUID: storageCommitmentPushModelSOPClassUID,
            requestedSOPInstanceUID: storageCommitmentPushModelSOPInstanceUID,
            actionTypeID: 99, hasDataSet: false, presentationContextID: 1)
        let actionReply = try await exchange(connection, command: wrongAction.commandSet)
        XCTAssertEqual(actionReply.command, .nActionResponse)
        XCTAssertEqual(actionReply.status?.rawValue, 0x0123)

        // PS3.7 §10.1.4.1.10: No such SOP Class (0118H)
        let wrongClass = NActionRequest(
            messageID: 2, requestedSOPClassUID: verificationSOPClass,
            requestedSOPInstanceUID: storageCommitmentPushModelSOPInstanceUID,
            actionTypeID: storageCommitmentRequestActionTypeID, hasDataSet: false, presentationContextID: 1)
        let classReply = try await exchange(connection, command: wrongClass.commandSet)
        XCTAssertEqual(classReply.command, .nActionResponse)
        XCTAssertEqual(classReply.status?.rawValue, 0x0118)

        await release(connection)
        await server.stop()
    }

    // 11. Commitment listener answers every N-EVENT-REPORT-RQ

    func testCommitmentListenerAnswersEventReportWithoutDataSet() async throws {
        let port: UInt16 = 19176
        let listener = CommitmentNotificationListener(
            configuration: CommitmentNotificationListenerConfiguration(aeTitle: try AETitle(Self.scpAE), port: port))
        try await listener.start()
        defer { Task { await listener.stop() } }
        try await Task.sleep(for: .milliseconds(200))

        let (connection, response) = try await associate(port: port, sopClass: storageCommitmentPushModelSOPClassUID)
        XCTAssertTrue(response is AssociateAcceptPDU, "Expected A-ASSOCIATE-AC, got \(response.pduType)")

        // No data set: Processing Failure (0110H), PS3.4 J.3.3.1.3 / PS3.7 §10.1.1.1.8
        var noDataSet = CommandSet()
        noDataSet.setCommand(.nEventReportRequest)
        noDataSet.setMessageID(3)
        noDataSet.setAffectedSOPClassUID(storageCommitmentPushModelSOPClassUID)
        noDataSet.setAffectedSOPInstanceUID(storageCommitmentPushModelSOPInstanceUID)
        noDataSet.setEventTypeID(storageCommitmentSuccessEventTypeID)
        noDataSet.setHasDataSet(false)
        let reply1 = try await exchange(connection, command: noDataSet)
        XCTAssertEqual(reply1.command, .nEventReportResponse)
        XCTAssertEqual(reply1.messageIDBeingRespondedTo, 3)
        XCTAssertEqual(reply1.status?.rawValue, 0x0110)

        // Missing Event Type ID: also answered with 0110H instead of dropping the association
        var noEventType = CommandSet()
        noEventType.setCommand(.nEventReportRequest)
        noEventType.setMessageID(4)
        noEventType.setAffectedSOPClassUID(storageCommitmentPushModelSOPClassUID)
        noEventType.setAffectedSOPInstanceUID(storageCommitmentPushModelSOPInstanceUID)
        noEventType.setHasDataSet(false)
        let reply2 = try await exchange(connection, command: noEventType)
        XCTAssertEqual(reply2.command, .nEventReportResponse)
        XCTAssertEqual(reply2.messageIDBeingRespondedTo, 4)
        XCTAssertEqual(reply2.status?.rawValue, 0x0110)

        await release(connection)
        await listener.stop()
    }

    // 9. The commitment listener also tests Protocol-version bit 0

    func testCommitmentListenerRejectsProtocolVersionWithoutBit0() async throws {
        let port: UInt16 = 19177
        let listener = CommitmentNotificationListener(
            configuration: CommitmentNotificationListenerConfiguration(aeTitle: try AETitle(Self.scpAE), port: port))
        try await listener.start()
        defer { Task { await listener.stop() } }
        try await Task.sleep(for: .milliseconds(200))

        let (connection, response) = try await associate(
            port: port, sopClass: storageCommitmentPushModelSOPClassUID, protocolVersion: 0x0000)
        let reject = try XCTUnwrap(response as? AssociateRejectPDU, "Expected A-ASSOCIATE-RJ, got \(response.pduType)")
        XCTAssertEqual(reject.result, .rejectedPermanent)
        XCTAssertEqual(reject.source, .serviceProviderACSE)
        XCTAssertEqual(reject.reason, 2)
        await connection.disconnect()
        await listener.stop()
    }
}

#endif
