import XCTest
import DICOMCore
@testable import DICOMNetwork

final class QueryServiceTests: XCTestCase {
    
    // MARK: - Query Configuration Tests
    
    func testQueryConfigurationDefaults() throws {
        let callingAE = try AETitle("CALLING")
        let calledAE = try AETitle("CALLED")
        
        let config = QueryConfiguration(
            callingAETitle: callingAE,
            calledAETitle: calledAE
        )
        
        XCTAssertEqual(config.callingAETitle.value, "CALLING")
        XCTAssertEqual(config.calledAETitle.value, "CALLED")
        XCTAssertEqual(config.timeout, 60)
        XCTAssertEqual(config.maxPDUSize, defaultMaxPDUSize)
        XCTAssertEqual(config.implementationClassUID, QueryConfiguration.defaultImplementationClassUID)
        XCTAssertEqual(config.implementationVersionName, QueryConfiguration.defaultImplementationVersionName)
        XCTAssertEqual(config.informationModel, .studyRoot)
    }
    
    func testQueryConfigurationCustomValues() throws {
        let callingAE = try AETitle("MY_SCU")
        let calledAE = try AETitle("PACS")
        
        let config = QueryConfiguration(
            callingAETitle: callingAE,
            calledAETitle: calledAE,
            timeout: 120,
            maxPDUSize: 32768,
            implementationClassUID: "1.2.3.4.5",
            implementationVersionName: "TEST_V1",
            informationModel: .patientRoot
        )
        
        XCTAssertEqual(config.callingAETitle.value, "MY_SCU")
        XCTAssertEqual(config.calledAETitle.value, "PACS")
        XCTAssertEqual(config.timeout, 120)
        XCTAssertEqual(config.maxPDUSize, 32768)
        XCTAssertEqual(config.implementationClassUID, "1.2.3.4.5")
        XCTAssertEqual(config.implementationVersionName, "TEST_V1")
        XCTAssertEqual(config.informationModel, .patientRoot)
    }
    
    func testQueryConfigurationHashable() throws {
        let callingAE = try AETitle("SCU")
        let calledAE = try AETitle("SCP")
        
        let config1 = QueryConfiguration(
            callingAETitle: callingAE,
            calledAETitle: calledAE,
            timeout: 60
        )
        let config2 = QueryConfiguration(
            callingAETitle: callingAE,
            calledAETitle: calledAE,
            timeout: 60
        )
        let config3 = QueryConfiguration(
            callingAETitle: callingAE,
            calledAETitle: calledAE,
            timeout: 120
        )
        
        XCTAssertEqual(config1, config2)
        XCTAssertNotEqual(config1, config3)
    }
    
    // MARK: - Default Implementation Constants Tests
    
    func testDefaultImplementationClassUID() {
        let uid = QueryConfiguration.defaultImplementationClassUID
        XCTAssertFalse(uid.isEmpty)
        XCTAssertTrue(uid.hasPrefix("1.2."))
    }
    
    func testDefaultImplementationVersionName() {
        let name = QueryConfiguration.defaultImplementationVersionName
        XCTAssertNotNil(name)
        XCTAssertFalse(name.isEmpty)
        XCTAssertTrue(name.contains("DICOMKIT"))
    }
    
    // MARK: - C-FIND Message Tests
    
    func testCFindRequestCreation() {
        let request = CFindRequest(
            messageID: 1,
            affectedSOPClassUID: studyRootQueryRetrieveFindSOPClassUID,
            priority: .medium,
            presentationContextID: 1
        )
        
        XCTAssertEqual(request.messageID, 1)
        XCTAssertEqual(request.affectedSOPClassUID, studyRootQueryRetrieveFindSOPClassUID)
        XCTAssertEqual(request.priority, .medium)
        XCTAssertEqual(request.presentationContextID, 1)
        XCTAssertTrue(request.hasDataSet)
        XCTAssertEqual(request.commandSet.command, .cFindRequest)
    }
    
    func testCFindRequestWithPatientRootModel() {
        let request = CFindRequest(
            messageID: 1,
            affectedSOPClassUID: patientRootQueryRetrieveFindSOPClassUID,
            priority: .high,
            presentationContextID: 3
        )
        
        XCTAssertEqual(request.affectedSOPClassUID, patientRootQueryRetrieveFindSOPClassUID)
        XCTAssertEqual(request.priority, .high)
        XCTAssertEqual(request.presentationContextID, 3)
    }
    
    func testCFindResponseCreation() {
        // Success response
        let successResponse = CFindResponse(
            messageIDBeingRespondedTo: 1,
            affectedSOPClassUID: studyRootQueryRetrieveFindSOPClassUID,
            status: .success,
            hasDataSet: false,
            presentationContextID: 1
        )
        
        XCTAssertEqual(successResponse.messageIDBeingRespondedTo, 1)
        XCTAssertEqual(successResponse.affectedSOPClassUID, studyRootQueryRetrieveFindSOPClassUID)
        XCTAssertTrue(successResponse.status.isSuccess)
        XCTAssertFalse(successResponse.hasDataSet)
        
        // Pending response
        let pendingResponse = CFindResponse(
            messageIDBeingRespondedTo: 1,
            affectedSOPClassUID: studyRootQueryRetrieveFindSOPClassUID,
            status: .pending(warningOptionalKeys: false),
            hasDataSet: true,
            presentationContextID: 1
        )
        
        XCTAssertTrue(pendingResponse.status.isPending)
        XCTAssertTrue(pendingResponse.hasDataSet)
    }
    
    func testCFindCommandSetEncoding() {
        let request = CFindRequest(
            messageID: 42,
            affectedSOPClassUID: studyRootQueryRetrieveFindSOPClassUID,
            priority: .medium,
            presentationContextID: 1
        )
        
        let encodedData = request.commandSet.encode()
        
        // Verify the command set can be encoded
        XCTAssertGreaterThan(encodedData.count, 0)
        
        // Verify round-trip decode
        do {
            let decodedCommandSet = try CommandSet.decode(from: encodedData)
            XCTAssertEqual(decodedCommandSet.command, .cFindRequest)
            XCTAssertEqual(decodedCommandSet.messageID, 42)
            XCTAssertEqual(decodedCommandSet.affectedSOPClassUID, studyRootQueryRetrieveFindSOPClassUID)
            XCTAssertTrue(decodedCommandSet.hasDataSet)
        } catch {
            XCTFail("Failed to decode command set: \(error)")
        }
    }
    
    // MARK: - Message Fragmentation Tests
    
    func testCFindRequestFragmentation() {
        let request = CFindRequest(
            messageID: 1,
            affectedSOPClassUID: studyRootQueryRetrieveFindSOPClassUID,
            presentationContextID: 1
        )
        
        // Create a sample identifier data set
        let identifierData = Data([0x08, 0x00, 0x52, 0x00]) // Query Retrieve Level tag
        
        let fragmenter = MessageFragmenter(maxPDUSize: 16384)
        let pdus = fragmenter.fragmentMessage(
            commandSet: request.commandSet,
            dataSet: identifierData,
            presentationContextID: 1
        )
        
        // Should have at least command and data set PDVs
        XCTAssertGreaterThanOrEqual(pdus.count, 2)
        
        // First PDU should be command
        let commandPDU = pdus[0]
        XCTAssertEqual(commandPDU.presentationDataValues.count, 1)
        XCTAssertTrue(commandPDU.presentationDataValues[0].isCommand)
    }
    
    // MARK: - Presentation Context Tests
    
    func testCFindPresentationContextCreation() throws {
        let context = try PresentationContext(
            id: 1,
            abstractSyntax: studyRootQueryRetrieveFindSOPClassUID,
            transferSyntaxes: [
                explicitVRLittleEndianTransferSyntaxUID,
                implicitVRLittleEndianTransferSyntaxUID
            ]
        )
        
        XCTAssertEqual(context.id, 1)
        XCTAssertEqual(context.abstractSyntax, studyRootQueryRetrieveFindSOPClassUID)
        XCTAssertEqual(context.transferSyntaxes.count, 2)
    }
    
    // MARK: - Message Assembly Tests
    
    func testCFindResponseAssembly() throws {
        // Create a C-FIND response (pending, with data set)
        let response = CFindResponse(
            messageIDBeingRespondedTo: 1,
            affectedSOPClassUID: studyRootQueryRetrieveFindSOPClassUID,
            status: .pending(warningOptionalKeys: false),
            hasDataSet: true,
            presentationContextID: 1
        )
        
        // Create sample data set
        let dataSetData = Data([0x08, 0x00, 0x52, 0x00, 0x43, 0x53, 0x06, 0x00, 0x53, 0x54, 0x55, 0x44, 0x59, 0x20])
        
        // Fragment it
        let fragmenter = MessageFragmenter(maxPDUSize: 16384)
        let pdus = fragmenter.fragmentMessage(
            commandSet: response.commandSet,
            dataSet: dataSetData,
            presentationContextID: 1
        )
        
        // Assemble it back
        let assembler = MessageAssembler()
        var assembledMessage: AssembledMessage?
        
        for pdu in pdus {
            assembledMessage = try assembler.addPDVs(from: pdu)
        }
        
        XCTAssertNotNil(assembledMessage)
        
        let findResponse = assembledMessage?.asCFindResponse()
        XCTAssertNotNil(findResponse)
        XCTAssertEqual(findResponse?.messageIDBeingRespondedTo, 1)
        XCTAssertTrue(findResponse?.status.isPending ?? false)
    }
    
    // MARK: - VR Extension Tests
    
    func testVRIsStringVR() {
        // String VRs
        XCTAssertTrue(VR.AE.isStringVR)
        XCTAssertTrue(VR.CS.isStringVR)
        XCTAssertTrue(VR.DA.isStringVR)
        XCTAssertTrue(VR.LO.isStringVR)
        XCTAssertTrue(VR.PN.isStringVR)
        XCTAssertTrue(VR.SH.isStringVR)
        XCTAssertTrue(VR.TM.isStringVR)
        XCTAssertTrue(VR.UI.isStringVR)
        
        // Non-string VRs
        XCTAssertFalse(VR.US.isStringVR)
        XCTAssertFalse(VR.UL.isStringVR)
        XCTAssertFalse(VR.OB.isStringVR)
        XCTAssertFalse(VR.OW.isStringVR)
    }
    
    /// D1 / D276: DICOMNetwork no longer carries its own Explicit VR length rule
    /// (`uses4ByteLength` omitted OV, SV and UV); every data-set walker uses
    /// DICOMCore's `VR.uses32BitLength`. PS3.5 2026a 7.1.2: AE, AS, AT, CS, DA, DS,
    /// DT, FL, FD, IS, LO, LT, PN, SH, SL, SS, ST, TM, UI, UL and US have a 16-bit
    /// Value Length (Table 7.1-2); all other VRs have 2 reserved bytes and a 32-bit
    /// Value Length (Table 7.1-1).
    func testVRUses32BitLengthIsDICOMCoreRule() {
        let sixteenBit: Set<VR> = [.AE, .AS, .AT, .CS, .DA, .DS, .DT, .FL, .FD, .IS, .LO, .LT,
                                   .PN, .SH, .SL, .SS, .ST, .TM, .UI, .UL, .US]
        let thirtyTwoBit: Set<VR> = [.OB, .OD, .OF, .OL, .OV, .OW, .SQ, .SV, .UC, .UN, .UR, .UT, .UV]
        XCTAssertEqual(sixteenBit.count + thirtyTwoBit.count, VR.allCases.count, "PS3.5 Table 6.2-1 lists 34 VRs")
        for vr in sixteenBit { XCTAssertFalse(vr.uses32BitLength, "\(vr)") }
        for vr in thirtyTwoBit { XCTAssertTrue(vr.uses32BitLength, "\(vr)") }
        // The three VRs the deleted duplicate omitted.
        XCTAssertTrue(VR.OV.uses32BitLength)
        XCTAssertTrue(VR.SV.uses32BitLength)
        XCTAssertTrue(VR.UV.uses32BitLength)
    }
    
    // MARK: - Error Type Tests
    
    func testQueryFailedError() {
        let error = DICOMNetworkError.queryFailed(.refusedOutOfResources)
        
        switch error {
        case .queryFailed(let status):
            XCTAssertTrue(status.isFailure)
            XCTAssertEqual(status.rawValue, 0xA700)
        default:
            XCTFail("Expected queryFailed error")
        }
        
        let description = error.description
        XCTAssertTrue(description.contains("Query failed"))
    }

    // MARK: - D1: 64-bit VRs on the wire (PS3.5 §7.1.2, Table 7.1-1)

    /// OV, SV and UV use the 4-byte length form in Explicit VR. A private copy of the
    /// length rule in DICOMNetwork omitted them, so a UV element was written with the
    /// 2-byte form and corrupted on the wire (DICOMCore report, D1).
    func test64BitVRsUseFourByteLengthInExplicitVR() {
        for vr in [VR.UV, VR.SV, VR.OV] {
            XCTAssertTrue(vr.uses32BitLength, "\(vr) uses the 32-bit length field (PS3.5 Table 7.1-1)")
            let keys = QueryKeys(level: .study).matching(Tag(group: 0x0072, element: 0x0082), value: "12", vr: vr)
            let data = DICOMQueryService.buildQueryIdentifier(
                level: .study, queryKeys: keys, transferSyntax: explicitVRLittleEndianTransferSyntaxUID)
            // Locate the element: tag (0072,0082) little endian, then the two VR bytes.
            let tagBytes: [UInt8] = [0x72, 0x00, 0x82, 0x00]
            let vrBytes = Array(vr.rawValue.utf8)
            guard let start = data.withUnsafeBytes({ raw -> Int? in
                let bytes = Array(raw)
                return (0..<(bytes.count - 12)).first { i in
                    Array(bytes[i..<i+4]) == tagBytes && Array(bytes[i+4..<i+6]) == vrBytes
                }
            }) else { return XCTFail("\(vr) element not found in the identifier") }
            let bytes = Array(data)
            XCTAssertEqual(Array(bytes[start+6..<start+8]), [0x00, 0x00], "\(vr): two reserved bytes follow the VR")
            let length = UInt32(bytes[start+8]) | UInt32(bytes[start+9]) << 8 | UInt32(bytes[start+10]) << 16 | UInt32(bytes[start+11]) << 24
            XCTAssertEqual(length, 2, "\(vr): 4-byte length field holds the (even) value length")
        }
        // The parser reads the 4-byte form back (round trip through the same rule).
        let keys = QueryKeys(level: .study).matching(Tag(group: 0x0072, element: 0x0082), value: "12", vr: .UV)
        let data = DICOMQueryService.buildQueryIdentifier(
            level: .study, queryKeys: keys, transferSyntax: explicitVRLittleEndianTransferSyntaxUID)
        let attrs = DICOMQueryService.parseQueryResponse(data: data, transferSyntax: explicitVRLittleEndianTransferSyntaxUID)
        XCTAssertEqual(attrs[Tag(group: 0x0072, element: 0x0082)], Data("12".utf8))
    }
}

// MARK: - Response parsing keeps sequences as single elements (PS3.5 7.5)

final class QueryResponseSequenceParsingTests: XCTestCase {

    private func le16(_ v: UInt16) -> Data { Data([UInt8(v & 0xFF), UInt8(v >> 8)]) }
    private func le32(_ v: UInt32) -> Data {
        Data([UInt8(v & 0xFF), UInt8((v >> 8) & 0xFF), UInt8((v >> 16) & 0xFF), UInt8((v >> 24) & 0xFF)])
    }
    /// Explicit VR LE element with a 2-byte-length VR.
    private func elem(_ g: UInt16, _ e: UInt16, _ vr: String, _ value: String) -> Data {
        var v = Data(value.utf8)
        if v.count % 2 != 0 { v.append(vr == "UI" ? 0x00 : 0x20) }
        return le16(g) + le16(e) + Data(vr.utf8) + le16(UInt16(v.count)) + v
    }
    private func item(undefinedLength: Bool, _ body: Data) -> Data {
        var d = Data([0xFE, 0xFF, 0x00, 0xE0])
        if undefinedLength {
            d += le32(0xFFFFFFFF) + body + Data([0xFE, 0xFF, 0x0D, 0xE0]) + le32(0)
        } else {
            d += le32(UInt32(body.count)) + body
        }
        return d
    }
    private func sequence(_ g: UInt16, _ e: UInt16, undefinedLength: Bool, items: [Data]) -> Data {
        let body = items.reduce(Data(), +)
        var d = le16(g) + le16(e) + Data("SQ".utf8) + Data([0, 0])
        if undefinedLength {
            d += le32(0xFFFFFFFF) + body + Data([0xFE, 0xFF, 0xDD, 0xE0]) + le32(0)
        } else {
            d += le32(UInt32(body.count)) + body
        }
        return d
    }

    private let refStudySeq = Tag(group: 0x0008, element: 0x1110)
    private let refSOPClass = Tag(group: 0x0008, element: 0x1150)
    private let refSOPInstance = Tag(group: 0x0008, element: 0x1155)

    func testUndefinedLengthSequenceItemsAreNotMergedIntoTopLevel() {
        let nested = elem(0x0008, 0x1150, "UI", "1.2.840.10008.3.1.2.3.1") + elem(0x0008, 0x1155, "UI", "1.2.3")
        let data = elem(0x0008, 0x0052, "CS", "STUDY")
            + sequence(0x0008, 0x1110, undefinedLength: true, items: [item(undefinedLength: true, nested)])
            + elem(0x0010, 0x0010, "PN", "DOE^JOHN")
        let attrs = DICOMQueryService.parseQueryResponse(data: data, transferSyntax: explicitVRLittleEndianTransferSyntaxUID)
        XCTAssertEqual(attrs[.patientName], Data("DOE^JOHN".utf8), "the element after the sequence is parsed")
        XCTAssertNil(attrs[refSOPClass], "nested (0008,1150) must not appear at the top level (PS3.5 7.5)")
        XCTAssertNil(attrs[refSOPInstance])
        XCTAssertEqual(attrs[refStudySeq], item(undefinedLength: true, nested), "raw sequence value kept under the SQ tag")
        XCTAssertEqual(attrs.count, 3)
    }

    func testDefinedLengthItemsInsideUndefinedLengthSequence() {
        let nested = elem(0x0008, 0x1150, "UI", "1.2.3.4")
        let data = sequence(0x0008, 0x1110, undefinedLength: true, items: [item(undefinedLength: false, nested), item(undefinedLength: false, nested)])
            + elem(0x0010, 0x0010, "PN", "DOE^JOHN")
        let attrs = DICOMQueryService.parseQueryResponse(data: data, transferSyntax: explicitVRLittleEndianTransferSyntaxUID)
        XCTAssertEqual(attrs[.patientName], Data("DOE^JOHN".utf8))
        XCTAssertNil(attrs[refSOPClass])
    }

    func testNestedUndefinedLengthSequenceInsideItem() {
        let inner = sequence(0x0008, 0x1140, undefinedLength: true,
                             items: [item(undefinedLength: true, elem(0x0008, 0x1150, "UI", "1.2.3.4"))])
        let data = sequence(0x0008, 0x1110, undefinedLength: true, items: [item(undefinedLength: true, inner)])
            + elem(0x0010, 0x0020, "LO", "P1")
        let attrs = DICOMQueryService.parseQueryResponse(data: data, transferSyntax: explicitVRLittleEndianTransferSyntaxUID)
        XCTAssertEqual(attrs[.patientID], Data("P1".utf8))
        XCTAssertNil(attrs[refSOPClass])
        XCTAssertNil(attrs[Tag(group: 0x0008, element: 0x1140)], "the inner sequence stays inside the outer item")
    }

    func testImplicitVRUndefinedLengthSequenceIsSkipped() {
        func ielem(_ g: UInt16, _ e: UInt16, _ value: String) -> Data {
            var v = Data(value.utf8); if v.count % 2 != 0 { v.append(0x20) }
            return le16(g) + le16(e) + le32(UInt32(v.count)) + v
        }
        let nested = ielem(0x0008, 0x1150, "1.2.3.4 ")
        var data = Data()
        data.append(le16(0x0008)); data.append(le16(0x1110)); data.append(le32(0xFFFFFFFF))
        data.append(Data([0xFE, 0xFF, 0x00, 0xE0])); data.append(le32(0xFFFFFFFF))
        data.append(nested)
        data.append(Data([0xFE, 0xFF, 0x0D, 0xE0])); data.append(le32(0))
        data.append(Data([0xFE, 0xFF, 0xDD, 0xE0])); data.append(le32(0))
        data.append(ielem(0x0010, 0x0010, "DOE^JOHN"))
        let attrs = DICOMQueryService.parseQueryResponse(data: data, transferSyntax: implicitVRLittleEndianTransferSyntaxUID)
        XCTAssertEqual(attrs[.patientName], Data("DOE^JOHN".utf8))
        XCTAssertNil(attrs[refSOPClass])
    }

    func testTruncatedUndefinedLengthSequenceStopsParsingWithoutMerging() {
        let nested = elem(0x0008, 0x1150, "UI", "1.2.3.4")
        var data = sequence(0x0008, 0x1110, undefinedLength: true, items: [item(undefinedLength: true, nested)])
        data.removeLast(8)   // drop the sequence delimiter
        let attrs = DICOMQueryService.parseQueryResponse(data: data, transferSyntax: explicitVRLittleEndianTransferSyntaxUID)
        XCTAssertNil(attrs[refSOPClass])
        XCTAssertNil(attrs[refStudySeq])
    }
}

// MARK: - C-FIND Identifier Character Set Tests (PS3.4 C.4.1.1.3.1, PS3.5 6.1.2)

final class QueryIdentifierCharacterSetTests: XCTestCase {

    /// Parses an Explicit VR LE identifier back into attributes with the same
    /// parser the service uses for responses.
    private func parse(_ data: Data) -> [Tag: Data] {
        DICOMQueryService.parseQueryResponse(data: data, transferSyntax: explicitVRLittleEndianTransferSyntaxUID)
    }

    func testASCIIKeysCarryNoSpecificCharacterSet() {
        let keys = QueryKeys(level: .study).patientName("DOE^JOHN*")
        let data = DICOMQueryService.buildQueryIdentifier(
            level: .study, queryKeys: keys, transferSyntax: explicitVRLittleEndianTransferSyntaxUID)
        let attrs = parse(data)
        XCTAssertNil(attrs[.specificCharacterSet], "ISO 646 values need no (0008,0005)")
        XCTAssertEqual(attrs[.patientName], "DOE^JOHN*".data(using: .ascii)! + Data([0x20]))
    }

    func testLatin1PatientNameInsertsISOIR100AndEncodesLatin1() {
        let keys = QueryKeys(level: .study).patientName("MÜLLER^HANS")
        let data = DICOMQueryService.buildQueryIdentifier(
            level: .study, queryKeys: keys, transferSyntax: explicitVRLittleEndianTransferSyntaxUID)
        let attrs = parse(data)
        XCTAssertEqual(attrs[.specificCharacterSet].flatMap { String(data: $0, encoding: .ascii) }, "ISO_IR 100")
        // Ü is a single 0xDC byte in ISO 8859-1; the value must not be empty (universal match).
        let expected = "MÜLLER^HANS".data(using: .isoLatin1)! + Data([0x20])
        XCTAssertEqual(attrs[.patientName], expected)
        XCTAssertTrue(attrs[.patientName]!.contains(0xDC))
    }

    func testNonLatin1PatientNameInsertsISOIR192AndEncodesUTF8() {
        let keys = QueryKeys(level: .study).patientName("山田^太郎")
        let data = DICOMQueryService.buildQueryIdentifier(
            level: .study, queryKeys: keys, transferSyntax: implicitVRLittleEndianTransferSyntaxUID)
        let attrs = DICOMQueryService.parseQueryResponse(data: data, transferSyntax: implicitVRLittleEndianTransferSyntaxUID)
        XCTAssertEqual(attrs[.specificCharacterSet].flatMap { String(data: $0, encoding: .ascii) }, "ISO_IR 192")
        // 13 UTF-8 bytes, space-padded to 14 (PS3.5 §6.2)
        XCTAssertEqual(attrs[.patientName], Data("山田^太郎".utf8) + Data([0x20]))
    }

    func testConfigurationOverrideForcesCharacterSet() {
        let keys = QueryKeys(level: .study).patientName("MÜLLER^HANS")
        let data = DICOMQueryService.buildQueryIdentifier(
            level: .study, queryKeys: keys, transferSyntax: explicitVRLittleEndianTransferSyntaxUID,
            specificCharacterSet: "ISO_IR 192")
        let attrs = parse(data)
        XCTAssertEqual(attrs[.specificCharacterSet].flatMap { String(data: $0, encoding: .ascii) }, "ISO_IR 192")
        // "MÜLLER^HANS" is 12 UTF-8 bytes (Ü is 2), already even: no pad (PS3.5 §6.2)
        XCTAssertEqual(attrs[.patientName], Data("MÜLLER^HANS".utf8))
    }

    func testCallerSuppliedSpecificCharacterSetKeyWinsOverOverride() {
        let keys = QueryKeys(level: .study)
            .matching(.specificCharacterSet, value: "ISO_IR 100", vr: .CS)
            .patientName("MÜLLER^HANS")
        let data = DICOMQueryService.buildQueryIdentifier(
            level: .study, queryKeys: keys, transferSyntax: explicitVRLittleEndianTransferSyntaxUID,
            specificCharacterSet: "ISO_IR 192")
        let attrs = parse(data)
        XCTAssertEqual(attrs[.specificCharacterSet].flatMap { String(data: $0, encoding: .ascii) }, "ISO_IR 100")
        XCTAssertTrue(attrs[.patientName]!.contains(0xDC))
        // Exactly one (0008,0005) element, ordered first (PS3.5 7.1)
        XCTAssertEqual(data[0..<4], Data([0x08, 0x00, 0x05, 0x00]))
    }

    func testQueryConfigurationCarriesSpecificCharacterSet() throws {
        let config = QueryConfiguration(
            callingAETitle: try AETitle("SCU"), calledAETitle: try AETitle("SCP"),
            specificCharacterSet: "ISO_IR 100")
        XCTAssertEqual(config.specificCharacterSet, "ISO_IR 100")
        let plain = QueryConfiguration(callingAETitle: try AETitle("SCU"), calledAETitle: try AETitle("SCP"))
        XCTAssertNil(plain.specificCharacterSet)
    }
}
