// dicom-server behaviour pinned to DICOM 2026a (DICOMCLI_STANDARD_IMPLEMENTATION.md, D94-D102).
// Table rows quoted here were dumped with Scripts/nema_docbook.py from the 2026a DocBook parts.
import XCTest
import Foundation
@testable import DICOMKit
@testable import DICOMCore
@testable import DICOMNetwork
@testable import dicom_server

final class DICOMServerStandardTests: XCTestCase {

    private let explicitLE = "1.2.840.10008.1.2.1"
    private let implicitLE = "1.2.840.10008.1.2"
    private let explicitBE = "1.2.840.10008.1.2.2"
    private let ctImageStorage = "1.2.840.10008.5.1.4.1.1.2"
    private let studyRootFind = "1.2.840.10008.5.1.4.1.2.2.1"
    private let studyRootGet = "1.2.840.10008.5.1.4.1.2.2.3"

    private func tempDir(_ name: String) -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("dicom-server-\(name)-\(UUID().uuidString)")
    }

    private func sampleDataSet(sopInstanceUID: String = "1.2.3.4.5.6.7",
                               studyUID: String = "1.2.3.4",
                               seriesUID: String = "1.2.3.4.5") -> DataSet {
        var ds = DataSet()
        ds.setString("Doe^Jane", for: .patientName, vr: .PN)
        ds.setString("PAT001", for: .patientID, vr: .LO)
        ds.setString(studyUID, for: .studyInstanceUID, vr: .UI)
        ds.setString("20260115", for: .studyDate, vr: .DA)
        ds.setString("101500", for: .studyTime, vr: .TM)
        ds.setString("ACC42", for: .accessionNumber, vr: .SH)
        ds.setString("S7", for: .studyID, vr: .SH)
        ds.setString(seriesUID, for: .seriesInstanceUID, vr: .UI)
        ds.setString("CT", for: .modality, vr: .CS)
        ds.setString("3", for: .seriesNumber, vr: .IS)
        ds.setString(ctImageStorage, for: .sopClassUID, vr: .UI)
        ds.setString(sopInstanceUID, for: .sopInstanceUID, vr: .UI)
        ds.setString("12", for: .instanceNumber, vr: .IS)
        return ds
    }

    // MARK: - D102: PS3.10 7.1 files, negotiated transfer syntax

    func test_D102_storedFileHasPreambleDICMAndFileMetaInformation() async throws {
        let dir = tempDir("d102")
        defer { try? FileManager.default.removeItem(at: dir) }
        let storage = try StorageManager(dataDirectory: dir.path)
        let received = ServerProtocol.encodeDataSet(sampleDataSet(), transferSyntaxUID: implicitLE)

        let stored = try await storage.storeReceived(
            dataSetData: received, sopClassUID: ctImageStorage, sopInstanceUID: "1.2.3.4.5.6.7",
            transferSyntaxUID: implicitLE, serverAETitle: "DICOMKIT_SCP", callingAETitle: "MODALITY1")

        let bytes = try Data(contentsOf: URL(fileURLWithPath: stored.filePath))
        // PS3.10 7.1: 128-byte File Preamble, then "DICM"
        XCTAssertEqual(bytes.prefix(128), Data(count: 128))
        XCTAssertEqual(String(data: bytes[128..<132], encoding: .ascii), "DICM")

        // Table 7.1-1 elements
        let file = try DICOMFile.read(from: bytes)
        let meta = file.fileMetaInformation
        XCTAssertEqual(meta[.fileMetaInformationVersion]?.valueData, Data([0x00, 0x01]))
        XCTAssertEqual(meta.string(for: .mediaStorageSOPClassUID), ctImageStorage)
        XCTAssertEqual(meta.string(for: .mediaStorageSOPInstanceUID), "1.2.3.4.5.6.7")
        XCTAssertEqual(meta.string(for: .transferSyntaxUID), implicitLE)
        XCTAssertEqual(meta.string(for: .implementationClassUID), DICOMFile.implementationClassUID)
        XCTAssertEqual(meta.string(for: .implementationVersionName), DICOMFile.implementationVersionName)
        XCTAssertEqual(meta.string(for: .sourceApplicationEntityTitle), "DICOMKIT_SCP")
        XCTAssertEqual(meta.string(for: Tag(group: 0x0002, element: 0x0017)), "MODALITY1")
        XCTAssertEqual(meta.string(for: Tag(group: 0x0002, element: 0x0018)), "DICOMKIT_SCP")
        // (0002,0000) counts the bytes after it up to the end of the group
        let groupLength = try XCTUnwrap(meta.uint32(for: .fileMetaInformationGroupLength))
        XCTAssertEqual(Data(bytes[(144 + Int(groupLength))...]), received, "data set stored as received")

        // The data set was decoded with the negotiated (implicit VR) syntax
        XCTAssertEqual(file.dataSet.string(for: .patientName), "Doe^Jane")
        XCTAssertEqual(file.dataSet.string(for: .accessionNumber), "ACC42")
        XCTAssertEqual(stored.dataSet.string(for: .studyID), "S7")
    }

    func test_D102_decodeUsesNegotiatedTransferSyntax() throws {
        let ds = sampleDataSet()
        for ts in [explicitLE, implicitLE, explicitBE] {
            let decoded = try ServerProtocol.decodeDataSet(ServerProtocol.encodeDataSet(ds, transferSyntaxUID: ts), transferSyntaxUID: ts)
            XCTAssertEqual(decoded.string(for: .patientID), "PAT001", ts)
            XCTAssertEqual(decoded.string(for: .seriesNumber), "3", ts)
            XCTAssertEqual(decoded.string(for: .sopInstanceUID), "1.2.3.4.5.6.7", ts)
        }
    }

    func test_D102_storedFileRoundTripsForCGet() async throws {
        let dir = tempDir("d102rt")
        defer { try? FileManager.default.removeItem(at: dir) }
        let storage = try StorageManager(dataDirectory: dir.path)
        let received = ServerProtocol.encodeDataSet(sampleDataSet(), transferSyntaxUID: explicitLE)
        let stored = try await storage.storeReceived(
            dataSetData: received, sopClassUID: ctImageStorage, sopInstanceUID: "1.2.3.4.5.6.7",
            transferSyntaxUID: explicitLE, serverAETitle: "SCP", callingAETitle: nil)
        let read = try ServerProtocol.readStoredFile(Data(contentsOf: URL(fileURLWithPath: stored.filePath)))
        XCTAssertEqual(read.dataSetData, received)
        XCTAssertEqual(read.transferSyntaxUID, explicitLE)
        XCTAssertEqual(read.sopClassUID, ctImageStorage)
        // Transcoding to the syntax of the requestor's context
        let implicitBytes = try ServerProtocol.transcode(read, to: implicitLE)
        XCTAssertEqual(try ServerProtocol.decodeDataSet(implicitBytes, transferSyntaxUID: implicitLE).string(for: .patientName), "Doe^Jane")
    }

    func test_D102_pathComponentsCannotLeaveTheDataDirectory() {
        XCTAssertEqual(StorageManager.pathComponent("../../etc"), ".._.._etc")
        XCTAssertEqual(StorageManager.pathComponent(".."), "_")
        XCTAssertEqual(StorageManager.pathComponent("1.2.840.10008"), "1.2.840.10008")
    }

    // MARK: - D94: AE titles (PS3.5 Table 6.2-1) and Implementation Class UID

    func test_D94_aeTitlesValidatedAsVRAE() throws {
        func config(_ ae: String, allowed: Set<String>? = nil, blocked: Set<String>? = nil) -> ServerConfiguration {
            ServerConfiguration(aeTitle: ae, port: 11112, dataDirectory: "/tmp/x", databaseURL: "",
                                allowedCallingAETitles: allowed, blockedCallingAETitles: blocked)
        }
        XCTAssertEqual(try config("ABCDEFGHIJKLMNOP").validated().aeTitle, "ABCDEFGHIJKLMNOP") // 16 chars
        XCTAssertEqual(try config("  PACS ").validated().aeTitle, "PACS")                     // spaces not significant
        XCTAssertThrowsError(try config("ABCDEFGHIJKLMNOPQ").validated())                      // 17 chars
        XCTAssertThrowsError(try config("A\\B").validated())                                   // backslash
        XCTAssertThrowsError(try config("A\tB").validated())                                   // control character
        XCTAssertThrowsError(try config("").validated())
        XCTAssertThrowsError(try config("PACS", allowed: ["GOOD", "WAY_TOO_LONG_AE_TITLE"]).validated())
        XCTAssertThrowsError(try config("PACS", blocked: ["BAD\\AE"]).validated())
    }

    func test_D94_implementationClassUIDUnderDICOMKitRoot() {
        XCTAssertTrue(ServerProtocol.implementationClassUID.hasPrefix("1.2.826.0.1.3680043.10.511."))
        XCTAssertEqual(ServerProtocol.implementationClassUID, DICOMFile.implementationClassUID)
        XCTAssertLessThanOrEqual(ServerProtocol.implementationVersionName.count, 16) // PS3.7 D.3.3.2
    }

    // MARK: - D95: Maximum Length (PS3.8 D.1)

    func test_D95_outgoingFragmentsBoundedByPeerMaximumLength() {
        XCTAssertEqual(ServerProtocol.outgoingMaxPDUSize(peer: 16384, local: 65536), 16384)
        XCTAssertEqual(ServerProtocol.outgoingMaxPDUSize(peer: 131072, local: 16384), 131072)
        XCTAssertEqual(ServerProtocol.outgoingMaxPDUSize(peer: 0, local: 16384), 16384) // 0 = no maximum
        XCTAssertEqual(ServerProtocol.outgoingMaxPDUSize(peer: 0, local: 0), defaultMaxPDUSize)

        // P-DATA-TF PDUs built for a 4096-byte peer never exceed it
        let fragmenter = MessageFragmenter(maxPDUSize: ServerProtocol.outgoingMaxPDUSize(peer: 4096, local: 65536))
        var cmd = CommandSet()
        cmd.setCommand(.cStoreRequest)
        for pdu in fragmenter.fragmentMessage(commandSet: cmd, dataSet: Data(count: 20000), presentationContextID: 1) {
            let encoded = try! pdu.encode()
            XCTAssertLessThanOrEqual(encoded.count - 6, 4096)
        }
    }

    func test_D95_incomingPDataCheckedAgainstOwnMaximum() {
        XCTAssertTrue(ServerProtocol.exceedsLocalMaximum(pduType: 0x04, length: 20000, localMax: 16384))
        XCTAssertFalse(ServerProtocol.exceedsLocalMaximum(pduType: 0x04, length: 16384, localMax: 16384))
        XCTAssertFalse(ServerProtocol.exceedsLocalMaximum(pduType: 0x01, length: 20000, localMax: 16384)) // RQ not limited
        XCTAssertFalse(ServerProtocol.exceedsLocalMaximum(pduType: 0x04, length: 20000, localMax: 0))
    }

    // MARK: - D97: role selection and sub-operation accounting

    func test_D97_roleSelectionAnsweredAndRequiredForCGetContexts() throws {
        let contexts = [
            try PresentationContext(id: 1, abstractSyntax: studyRootGet, transferSyntaxes: [explicitLE]),
            try PresentationContext(id: 3, abstractSyntax: ctImageStorage, transferSyntaxes: [implicitLE]),
            try PresentationContext(id: 5, abstractSyntax: "1.2.840.10008.5.1.4.1.1.4", transferSyntaxes: [explicitLE]),
            try PresentationContext(id: 7, abstractSyntax: "1.2.3.999", transferSyntaxes: [explicitLE]),
            try PresentationContext(id: 9, abstractSyntax: ctImageStorage, transferSyntaxes: ["1.2.840.10008.1.2.4.50"]),
        ]
        let n = ServerProtocol.negotiate(presentationContexts: contexts,
                                         roleSelections: [SCPSCURoleSelection.both(ctImageStorage)])
        // PS3.8 Table 9-18 results
        XCTAssertEqual(n.results.map(\.result), [.acceptance, .acceptance, .acceptance, .abstractSyntaxNotSupported, .transferSyntaxesNotSupported])
        // PS3.7 D.3.3.4: answered for CT, SCP role granted; MR without a proposal keeps default roles
        XCTAssertEqual(n.roleSelections, [SCPSCURoleSelection(sopClassUID: ctImageStorage, scuRole: true, scpRole: true)])
        XCTAssertEqual(n.accepted[3]?.requestorIsSCP, true)
        XCTAssertEqual(n.accepted[5]?.requestorIsSCP, false)
        XCTAssertEqual(n.accepted[3]?.transferSyntax, implicitLE)
    }

    func test_D97_subOperationCountsFromCStoreResponseStatus() {
        var counts = ServerProtocol.SubOperationCounts(total: 5)
        counts.record(.success, sopInstanceUID: "1")
        counts.record(.warningCoercionOfDataElements, sopInstanceUID: "2")          // B000
        counts.record(DIMSEStatus.from(0xB007), sopInstanceUID: "3")                // B007
        counts.record(.refusedOutOfResources, sopInstanceUID: "4")                  // A700
        counts.record(nil, sopInstanceUID: "5")                                     // not initiated
        XCTAssertEqual(counts.remaining, 0)
        XCTAssertEqual(counts.completed, 1)
        XCTAssertEqual(counts.warning, 2)
        XCTAssertEqual(counts.failed, 2)
        XCTAssertEqual(counts.failedSOPInstanceUIDs, ["4", "5"])
        let identifier = ServerProtocol.failedInstancesIdentifier(counts)
        XCTAssertEqual(identifier?.strings(for: .failedSOPInstanceUIDList), ["4", "5"])  // (0008,0058)
    }

    func test_D97_finalStatusPerC4_3_3_1() {
        func status(_ outcomes: [DIMSEStatus?], cancelled: Bool = false) -> UInt16 {
            var c = ServerProtocol.SubOperationCounts(total: outcomes.count)
            for (i, s) in outcomes.enumerated() { c.record(s, sopInstanceUID: "\(i)") }
            return ServerProtocol.finalRetrieveStatus(c, cancelled: cancelled).rawValue
        }
        XCTAssertEqual(status([]), 0x0000)
        XCTAssertEqual(status([.success, .success]), 0x0000)                     // Success
        XCTAssertEqual(status([.success, nil]), 0xB000)                          // one or more failures
        XCTAssertEqual(status([.success, .warningElementsDiscarded]), 0xB000)    // warning
        XCTAssertEqual(status([.warningCoercionOfDataElements]), 0xB000)         // all warning
        XCTAssertEqual(status([nil, .refusedOutOfResources]), 0xA702)            // all unsuccessful
        XCTAssertEqual(status([.success], cancelled: true), 0xFE00)              // Cancel
        XCTAssertNil(ServerProtocol.failedInstancesIdentifier(ServerProtocol.SubOperationCounts(total: 0)))
    }

    // MARK: - D101: Query/Retrieve Level

    func test_D101_missingLevelIsA900WithOffendingElement() throws {
        var identifier = DataSet()
        identifier.setString("PAT001", for: .patientID, vr: .LO)
        guard case .failure(let error) = ServerProtocol.queryRetrieveLevel(in: identifier, sopClassUID: studyRootFind) else {
            return XCTFail("missing level accepted")
        }
        XCTAssertEqual(error.status.rawValue, 0xA900) // Tables C.4-1..C.4-3
        XCTAssertEqual(error.offendingElement, .queryRetrieveLevel)
        var cmd = CommandSet()
        ServerProtocol.addErrorFields(error, to: &cmd)
        XCTAssertEqual(cmd.getData(.offendingElement), Data([0x08, 0x00, 0x52, 0x00])) // AT (0008,0052)
        XCTAssertEqual(cmd.getString(.errorComment), "Query/Retrieve Level (0008,0052) missing")
    }

    func test_D101_levelValuesPerModel() {
        func level(_ value: String, _ sop: String) -> QueryLevel? {
            var ds = DataSet()
            ds.setString(value, for: .queryRetrieveLevel, vr: .CS)
            return try? ServerProtocol.queryRetrieveLevel(in: ds, sopClassUID: sop).get()
        }
        let patientRootFind = "1.2.840.10008.5.1.4.1.2.1.1"
        // Table C.6.1-1 (Patient Root): PATIENT, STUDY, SERIES, IMAGE
        XCTAssertEqual(["PATIENT", "STUDY", "SERIES", "IMAGE"].compactMap { level($0, patientRootFind) }, [.patient, .study, .series, .image])
        // Table C.6.2-1 (Study Root): STUDY, SERIES, IMAGE
        XCTAssertNil(level("PATIENT", studyRootFind))
        XCTAssertEqual(level("IMAGE", studyRootFind), .image)
        XCTAssertNil(level("INSTANCE", studyRootFind))
    }

    // MARK: - D98 / D100: matching and keys (PS3.4 C.2.2.2, Tables C.6-1..C.6-5)

    /// Required (R) and Unique (U) keys, dumped from part04_2026a.xml Tables C.6-1..C.6-5.
    private let requiredAndUniqueKeys: [(Tag, QueryLevel)] = [
        (.patientName, .patient), (.patientID, .patient),                                   // C.6-1
        (.studyDate, .study), (.studyTime, .study), (.accessionNumber, .study),             // C.6-2
        (.studyID, .study), (.studyInstanceUID, .study),
        (.modality, .series), (.seriesNumber, .series), (.seriesInstanceUID, .series),      // C.6-3
        (.instanceNumber, .image), (.sopInstanceUID, .image),                               // C.6-4
    ]

    func test_D100_allRequiredAndUniqueKeysSupported() {
        for (tag, level) in requiredAndUniqueKeys {
            XCTAssertTrue(QueryMatcher.supportedKeys(at: level).contains { $0.tag == tag }, "\(tag) at \(level)")
        }
        // C.6-5: the Study Root study level includes Patient's Name and Patient ID
        let studyKeys = Set(QueryMatcher.supportedKeys(at: .study).map(\.tag))
        XCTAssertTrue(studyKeys.isSuperset(of: [.patientName, .patientID]))
    }

    func test_D98_wildcardOnlyForListedVRsAndCaseSensitiveExceptPN() {
        // C.2.2.2.4: wildcard VRs
        XCTAssertEqual(QueryMatcher.wildcardVRs, [.AE, .CS, .LO, .LT, .PN, .SH, .ST, .UC, .UR, .UT])
        XCTAssertTrue(QueryMatcher.matches(values: ["ACC42"], key: "ACC*", vr: .SH))
        XCTAssertTrue(QueryMatcher.matches(values: ["ACC42"], key: "ACC?2", vr: .SH))
        XCTAssertFalse(QueryMatcher.matches(values: ["ACC42"], key: "acc*", vr: .SH))       // case-sensitive
        XCTAssertFalse(QueryMatcher.matches(values: ["CT"], key: "ct", vr: .CS))            // single value, case-sensitive
        XCTAssertTrue(QueryMatcher.matches(values: ["Doe^Jane"], key: "DOE*", vr: .PN))     // PN insensitive
        XCTAssertTrue(QueryMatcher.matches(values: ["Doe^Jane"], key: "doe^jane", vr: .PN))
        // UI is not a wildcard VR: "*" is a literal
        XCTAssertFalse(QueryMatcher.matches(values: ["1.2.3.4"], key: "1.2.*", vr: .UI))
        // "*" alone is Universal Matching for a wildcard VR
        XCTAssertTrue(QueryMatcher.matches(values: ["X"], key: "*", vr: .LO))
    }

    func test_D98_listOfUIDUniversalAndRangeMatching() {
        // C.2.2.2.2 List of UID Matching
        XCTAssertTrue(QueryMatcher.matches(values: ["1.2.3"], key: "1.2.9\\1.2.3", vr: .UI))
        XCTAssertFalse(QueryMatcher.matches(values: ["1.2.3"], key: "1.2.9\\1.2.4", vr: .UI))
        // C.2.2.2.3 Universal Matching (also when the entity has no value)
        XCTAssertTrue(QueryMatcher.matches(values: nil, key: "", vr: .LO))
        XCTAssertFalse(QueryMatcher.matches(values: nil, key: "X", vr: .LO))
        // C.2.2.2.5.1 DA ranges
        XCTAssertTrue(QueryMatcher.matches(values: ["20260115"], key: "20260101-20260131", vr: .DA))
        XCTAssertTrue(QueryMatcher.matches(values: ["20260115"], key: "-20260115", vr: .DA))
        XCTAssertTrue(QueryMatcher.matches(values: ["20260115"], key: "20260115-", vr: .DA))
        XCTAssertFalse(QueryMatcher.matches(values: ["20260115"], key: "20260116-", vr: .DA))
        // C.2.2.2.5.2 TM ranges, inclusive; C.2.2.2.1.3 TM by meaning
        XCTAssertTrue(QueryMatcher.matches(values: ["101500"], key: "1000-1100", vr: .TM))
        XCTAssertTrue(QueryMatcher.matches(values: ["101500"], key: "-10", vr: .TM))
        XCTAssertFalse(QueryMatcher.matches(values: ["101500"], key: "1016-", vr: .TM))
        XCTAssertTrue(QueryMatcher.matches(values: ["2230"], key: "223000", vr: .TM))
        // IS by value (C.2.2.2.1.4)
        XCTAssertTrue(QueryMatcher.matches(values: ["3"], key: "003", vr: .IS))
    }

    func test_D100_responseCarriesRequestedKeysLevelAndRetrieveAE() async throws {
        let db = try DatabaseManager(connectionString: "")
        try await db.index(filePath: "/tmp/a.dcm", metadata: DICOMMetadata(dataSet: sampleDataSet(), filePath: "/tmp/a.dcm"))

        var query = DataSet()
        query.setString("STUDY", for: .queryRetrieveLevel, vr: .CS)
        query.setString("ACC42", for: .accessionNumber, vr: .SH)
        query.setString("1000-1100", for: .studyTime, vr: .TM)
        query.setString("S7", for: .studyID, vr: .SH)
        query.setString("", for: .studyInstanceUID, vr: .UI)
        query.setString("", for: .patientName, vr: .PN)
        query.setString("", for: .studyDescription, vr: .LO)   // supported, no value
        let results = try await db.queryForFind(queryDataset: query, level: .study, retrieveAETitle: "DICOMKIT_SCP")
        XCTAssertEqual(results.count, 1)
        let r = try XCTUnwrap(results.first)
        XCTAssertEqual(r.string(for: .accessionNumber), "ACC42")
        XCTAssertEqual(r.string(for: .studyTime), "101500")
        XCTAssertEqual(r.string(for: .studyID), "S7")
        XCTAssertEqual(r.string(for: .studyInstanceUID), "1.2.3.4")
        XCTAssertEqual(r.string(for: .patientName), "Doe^Jane")
        XCTAssertEqual(r[.studyDescription]?.length, 0)                       // zero length, still present
        XCTAssertEqual(r.string(for: .queryRetrieveLevel), "STUDY")           // C.4.1.1.3.2
        XCTAssertEqual(r.string(for: Tag(group: 0x0008, element: 0x0054)), "DICOMKIT_SCP")
        XCTAssertNil(r[.patientID], "keys not in the request are not returned")
        XCTAssertNil(r[.modality])

        // A non-matching Required key excludes the study
        query.setString("ACC43", for: .accessionNumber, vr: .SH)
        let none = try await db.queryForFind(queryDataset: query, level: .study)
        XCTAssertTrue(none.isEmpty)
    }

    func test_D100_seriesNumberAndInstanceNumberMatched() async throws {
        let db = try DatabaseManager(connectionString: "")
        try await db.index(filePath: "/tmp/a.dcm", metadata: DICOMMetadata(dataSet: sampleDataSet(), filePath: "/tmp/a.dcm"))
        var series = DataSet()
        series.setString("3", for: .seriesNumber, vr: .IS)
        series.setString("", for: .seriesInstanceUID, vr: .UI)
        let seriesHit = try await db.queryForFind(queryDataset: series, level: .series)
        XCTAssertEqual(seriesHit.first?.string(for: .seriesInstanceUID), "1.2.3.4.5")
        series.setString("4", for: .seriesNumber, vr: .IS)
        let seriesMiss = try await db.queryForFind(queryDataset: series, level: .series)
        XCTAssertTrue(seriesMiss.isEmpty)

        var image = DataSet()
        image.setString("12", for: .instanceNumber, vr: .IS)
        image.setString("", for: .sopInstanceUID, vr: .UI)
        let imageHit = try await db.queryForFind(queryDataset: image, level: .image)
        XCTAssertEqual(imageHit.first?.string(for: .sopInstanceUID), "1.2.3.4.5.6.7")
    }

    func test_D100_unsupportedOptionalKeysReported() {
        var query = DataSet()
        query.setString("STUDY", for: .queryRetrieveLevel, vr: .CS)
        query.setString("", for: .studyInstanceUID, vr: .UI)
        query.setString("", for: Tag(group: 0x0008, element: 0x0090), vr: .PN) // Referring Physician's Name
        XCTAssertEqual(QueryMatcher.unsupportedKeys(in: query, level: .study), [Tag(group: 0x0008, element: 0x0090)])
    }

    // MARK: - D96: Move Destination

    func test_D96_unknownMoveDestinationResolvesToNil() throws {
        let config = try ServerConfiguration(
            aeTitle: "SCP", port: 11112, dataDirectory: "/tmp/x", databaseURL: "",
            knownDestinations: ["WORKSTATION": DestinationAE(host: "10.0.0.5", port: 104, aeTitle: "WORKSTATION")]
        ).validated()
        XCTAssertEqual(config.moveDestination(for: "WORKSTATION")?.host, "10.0.0.5")
        XCTAssertNil(config.moveDestination(for: "UNKNOWN_AE"))                 // -> A801
        XCTAssertEqual(config.moveDestination(for: "127.0.0.1:4242:X")?.port, 4242) // explicit host:port:AE form
        XCTAssertEqual(DIMSEStatus.failedMoveDestinationUnknown.rawValue, 0xA801) // Table C.4-2
        let (ae, dest) = try ServerConfiguration.parseDestination("STORE_SCP=192.168.1.9:11112")
        XCTAssertEqual(ae, "STORE_SCP")
        XCTAssertEqual(dest.port, 11112)
        XCTAssertThrowsError(try ServerConfiguration.parseDestination("NOPORT=host"))
    }

    // MARK: - Loopback: C-ECHO, C-STORE, C-FIND, C-GET, C-MOVE (DICOMNetwork SCUs)

    private func startServer(ae: String, dir: URL, destinations: [String: DestinationAE] = [:]) async throws -> (PACSServer, UInt16, Task<Void, Error>) {
        for _ in 0..<5 {
            let port = UInt16.random(in: 40000...60000)
            let config = ServerConfiguration(aeTitle: ae, port: port, dataDirectory: dir.path, databaseURL: "sqlite://\(dir.path)/index.db",
                                             maxPDUSize: 16384, knownDestinations: destinations)
            let server = try PACSServer(configuration: config)
            let task = Task { try await server.start() }
            for _ in 0..<40 {
                try await Task.sleep(nanoseconds: 50_000_000)
                if (try? await DICOMVerificationService.echo(host: "127.0.0.1", port: port, callingAE: "TEST_SCU", calledAE: ae, timeout: 2))?.success == true {
                    return (server, port, task)
                }
            }
            await server.stop()
            task.cancel()
        }
        throw XCTSkip("could not start a loopback listener")
    }

    func test_loopback_echoStoreFindGetMove() async throws {
        let dirA = tempDir("loopA"), dirB = tempDir("loopB")
        defer { try? FileManager.default.removeItem(at: dirA); try? FileManager.default.removeItem(at: dirB) }

        let (serverB, portB, taskB) = try await startServer(ae: "DEST_SCP", dir: dirB)
        let (serverA, portA, taskA) = try await startServer(
            ae: "DICOMKIT_SCP", dir: dirA,
            destinations: ["DEST_SCP": DestinationAE(host: "127.0.0.1", port: portB, aeTitle: "DEST_SCP")])
        defer { taskA.cancel(); taskB.cancel() }

        // C-ECHO (PS3.7 9.1.5)
        let echo = try await DICOMVerificationService.echo(host: "127.0.0.1", port: portA, callingAE: "TEST_SCU", calledAE: "DICOMKIT_SCP", timeout: 5)
        XCTAssertEqual(echo.status.rawValue, 0x0000)

        // C-STORE in Implicit VR Little Endian
        let ds = sampleDataSet()
        let store = try await DICOMStorageService.store(
            dataSetData: ServerProtocol.encodeDataSet(ds, transferSyntaxUID: implicitLE),
            sopClassUID: ctImageStorage, sopInstanceUID: "1.2.3.4.5.6.7", transferSyntaxUID: implicitLE,
            to: "127.0.0.1", port: portA, callingAE: "TEST_SCU", calledAE: "DICOMKIT_SCP", timeout: 5)
        XCTAssertEqual(store.status.rawValue, 0x0000)
        let storedPath = dirA.appendingPathComponent("1.2.3.4/1.2.3.4.5/1.2.3.4.5.6.7.dcm")
        let file = try DICOMFile.read(from: Data(contentsOf: storedPath))
        XCTAssertEqual(file.fileMetaInformation.string(for: .transferSyntaxUID), implicitLE)
        XCTAssertEqual(file.dataSet.string(for: .patientName), "Doe^Jane")

        // C-FIND (Study Root, STUDY level)
        let studies = try await DICOMQueryService.findStudies(
            host: "127.0.0.1", port: portA, callingAE: "TEST_SCU", calledAE: "DICOMKIT_SCP",
            matching: QueryKeys(level: .study).accessionNumber("ACC*").requestStudyInstanceUID().requestStudyID(),
            timeout: 5)
        XCTAssertEqual(studies.count, 1)
        XCTAssertEqual(studies.first?.studyInstanceUID, "1.2.3.4")
        XCTAssertEqual(studies.first?.studyID, "S7")

        // C-GET: the sub-operation's C-STORE-RSP is awaited and counted
        var received: [String] = []
        var getResult: RetrieveResult?
        for await event in try await DICOMRetrieveService.getStudy(
            host: "127.0.0.1", port: portA, callingAE: "TEST_SCU", calledAE: "DICOMKIT_SCP",
            studyInstanceUID: "1.2.3.4", storageSopClasses: [ctImageStorage], timeout: 5) {
            switch event {
            case .instance(let uid, _, _, _): received.append(uid)
            case .completed(let r): getResult = r
            default: break
            }
        }
        XCTAssertEqual(received, ["1.2.3.4.5.6.7"])
        XCTAssertEqual(getResult?.status.rawValue, 0x0000)
        XCTAssertEqual(getResult?.progress.completed, 1)
        XCTAssertEqual(getResult?.progress.failed, 0)

        // C-MOVE to an unknown destination: A801 (Table C.4-2)
        let refused = try await DICOMRetrieveService.moveStudy(
            host: "127.0.0.1", port: portA, callingAE: "TEST_SCU", calledAE: "DICOMKIT_SCP",
            studyInstanceUID: "1.2.3.4", moveDestination: "NOWHERE", timeout: 5)
        XCTAssertEqual(refused.status.rawValue, 0xA801)

        // C-MOVE to a configured destination (server B)
        let moved = try await DICOMRetrieveService.moveStudy(
            host: "127.0.0.1", port: portA, callingAE: "TEST_SCU", calledAE: "DICOMKIT_SCP",
            studyInstanceUID: "1.2.3.4", moveDestination: "DEST_SCP", timeout: 10)
        XCTAssertEqual(moved.status.rawValue, 0x0000)
        XCTAssertEqual(moved.progress.completed, 1)
        let movedFile = try DICOMFile.read(from: Data(contentsOf: dirB.appendingPathComponent("1.2.3.4/1.2.3.4.5/1.2.3.4.5.6.7.dcm")))
        XCTAssertEqual(movedFile.dataSet.string(for: .accessionNumber), "ACC42")

        await serverA.stop()
        await serverB.stop()
    }
}
