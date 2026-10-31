import XCTest
import Foundation
import ArgumentParser
@testable import DICOMCore
@testable import DICOMKit
@testable import DICOMNetwork
@testable import dicom_server

final class M4DurabilityTests: XCTestCase {
    private let instance = "1.2.826.0.1.3680043.10.900.1"
    private let study = "1.2.826.0.1.3680043.10.900.2"
    private let series = "1.2.826.0.1.3680043.10.900.3"
    private let sopClass = "1.2.840.10008.5.1.4.1.1.2"
    private let explicitLE = "1.2.840.10008.1.2.1"

    private func directory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("m4-durable-\(UUID().uuidString)")
    }
    private func dataset(name: String = "Restart^Patient") -> DataSet {
        var ds = DataSet()
        ds.setString(instance, for: .sopInstanceUID, vr: .UI)
        ds.setString(sopClass, for: .sopClassUID, vr: .UI)
        ds.setString(study, for: .studyInstanceUID, vr: .UI)
        ds.setString(series, for: .seriesInstanceUID, vr: .UI)
        ds.setString("RESTART001", for: .patientID, vr: .LO)
        ds.setString(name, for: .patientName, vr: .PN)
        ds.setString("CT", for: .modality, vr: .CS)
        ds.setString("1", for: .instanceNumber, vr: .IS)
        return ds
    }
    private func store(_ storage: StorageManager, name: String = "Restart^Patient", syntax: String = "1.2.840.10008.1.2.1") async throws -> StorageManager.StoredInstance {
        try await storage.storeReceived(dataSetData: ServerProtocol.encodeDataSet(dataset(name: name), transferSyntaxUID: syntax),
            sopClassUID: sopClass, sopInstanceUID: instance, transferSyntaxUID: syntax, serverAETitle: "SCP", callingAETitle: "SCU")
    }
    private func query() -> DataSet {
        var ds = DataSet()
        ds.setString("IMAGE", for: .queryRetrieveLevel, vr: .CS)
        ds.setString(instance, for: .sopInstanceUID, vr: .UI)
        return ds
    }
    private func fails(_ contains: String, _ operation: () async throws -> Void, file: StaticString = #filePath, line: UInt = #line) async {
        do { try await operation(); XCTFail("Expected failure containing \(contains)", file: file, line: line) }
        catch { XCTAssertTrue(String(describing: error).contains(contains), "\(error)", file: file, line: line) }
    }

    #if canImport(Network)
    func testServerConcurrentStopThenSameObjectRestartRetainsExclusiveOwnership() async throws {
        let dir = directory(); defer { try? FileManager.default.removeItem(at: dir) }
        let port = UInt16.random(in: 40000...60000)
        let config = ServerConfiguration(aeTitle: "M4SCP", port: port, dataDirectory: dir.path, databaseURL: "filesystem://")
        let server = try PACSServer(configuration: config)
        func ready() async throws {
            for _ in 0..<50 {
                if (try? await DICOMVerificationService.echo(host: "127.0.0.1", port: port,
                    callingAE: "M4SCU", calledAE: "M4SCP", timeout: 0.2))?.success == true { return }
                try await Task.sleep(nanoseconds: 20_000_000)
            }
            throw ServerError.invalidConfiguration("Loopback listener did not become ready")
        }
        let first = Task { try await server.start() }
        do { try await ready() } catch { await server.stop(); first.cancel(); _ = try? await first.value; throw error }
        await fails("already running") { try await server.start() }
        let stopA = Task { await server.stop() }, stopB = Task { await server.stop() }
        await stopA.value; await stopB.value
        try await first.value
        let second = Task { try await server.start() }
        do {
            try await ready()
            let competitor = try StorageManager(dataDirectory: dir.path)
            await fails("already in use") { try await competitor.acquireExclusiveAccess() }
            await server.stop()
            try await second.value
            try await competitor.acquireExclusiveAccess()
            await competitor.releaseExclusiveAccess()
        } catch { await server.stop(); second.cancel(); _ = try? await second.value; throw error }
    }
    #endif

    func testDefaultAndExplicitBackendContracts() throws {
        XCTAssertEqual(try StartCommand.parse([]).createConfiguration().databaseURL, "filesystem://")
        XCTAssertEqual(try StartCommand.parse(["--database", "none"]).createConfiguration().databaseURL, "")
        XCTAssertEqual(try StartCommand.parse(["--database-url", "filesystem://"]).createConfiguration().databaseURL, "filesystem://")
        for arguments in [["--database", "sqlite"], ["--database", "postgres"],
                          ["--database-url", "sqlite:///tmp/old.db"], ["--database-url", "postgresql://localhost/db"]] {
            XCTAssertThrowsError(try StartCommand.parse(arguments).createConfiguration()) { error in
                XCTAssertTrue(String(describing: error).contains("--database filesystem"))
            }
        }
        XCTAssertThrowsError(try ServerConfiguration(aeTitle: "SCP", port: 11112, dataDirectory: "/tmp/x", databaseURL: "sqlite:///tmp/old.db").validated())
    }

    #if canImport(Darwin)
    func testMacOSTemporaryAliasUsesCanonicalRootWithoutWeakeningSymlinkRefusal() async throws {
        let name = "m4-platform-alias-\(UUID().uuidString)"
        let aliasRoot = URL(fileURLWithPath: "/tmp/" + name)
        defer { try? FileManager.default.removeItem(at: aliasRoot) }
        let storage = try StorageManager(dataDirectory: aliasRoot.path)
        let saved = try await store(storage)
        XCTAssertTrue(saved.filePath.hasPrefix("/private/tmp/" + name + "/"), saved.filePath)
        let records = try await storage.scanForIndex()
        XCTAssertEqual(records.count, 1)
        try FileManager.default.createSymbolicLink(at: aliasRoot.appendingPathComponent("unsafe"),
            withDestinationURL: URL(fileURLWithPath: saved.filePath).deletingLastPathComponent())
        await fails("symbolic link") { _ = try await storage.scanForIndex() }
    }
    #endif

    func testFreshManagersReindexSameIdentityAndExactStoredBytes() async throws {
        let dir = directory(); defer { try? FileManager.default.removeItem(at: dir) }
        let first = try StorageManager(dataDirectory: dir.path)
        let saved = try await store(first)
        let original = try Data(contentsOf: URL(fileURLWithPath: saved.filePath))
        let restarted = try StorageManager(dataDirectory: dir.path)
        let database = try DatabaseManager(connectionString: "filesystem://")
        try await database.initialize(storage: restarted)
        let count = await database.instanceCount
        XCTAssertEqual(count, 1)
        let found = try await database.queryForFind(queryDataset: query(), level: .image)
        XCTAssertEqual(found.map { $0.string(for: .sopInstanceUID) }, [instance])
        let retrieved = try await database.queryForRetrieve(queryDataset: query(), level: .image)
        XCTAssertEqual(retrieved.map(\.sopInstanceUID), [instance])
        XCTAssertEqual(try Data(contentsOf: URL(fileURLWithPath: XCTUnwrap(retrieved.first).filePath)), original)
        let payload = try ServerProtocol.readStoredFile(original)
        XCTAssertEqual(payload.dataSetData, ServerProtocol.encodeDataSet(dataset(), transferSyntaxUID: explicitLE))
    }

    func testExactRetransmissionIsIdempotentAndConflictPreservesOriginal() async throws {
        let dir = directory(); defer { try? FileManager.default.removeItem(at: dir) }
        let storage = try StorageManager(dataDirectory: dir.path)
        let saved = try await store(storage)
        let original = try Data(contentsOf: URL(fileURLWithPath: saved.filePath))
        let again = try await store(storage)
        XCTAssertEqual(saved.filePath, again.filePath)
        let otherSender = try await storage.storeReceived(dataSetData: ServerProtocol.encodeDataSet(dataset(), transferSyntaxUID: explicitLE),
            sopClassUID: sopClass, sopInstanceUID: instance, transferSyntaxUID: explicitLE, serverAETitle: "OTHER_SCP", callingAETitle: "OTHER_SCU")
        XCTAssertEqual(otherSender.filePath, saved.filePath)

        await fails("Conflicting content") { _ = try await self.store(storage, name: "Different^Patient") }
        XCTAssertEqual(try Data(contentsOf: URL(fileURLWithPath: saved.filePath)), original)
        let count = try await storage.scanForIndex().count
        XCTAssertEqual(count, 1)
    }

    func testDuplicateUIDPathsFailDeterministicallyWithoutPartialIndex() async throws {
        let dir = directory(); defer { try? FileManager.default.removeItem(at: dir) }
        let storage = try StorageManager(dataDirectory: dir.path)
        let saved = try await store(storage)
        try FileManager.default.copyItem(atPath: saved.filePath, toPath: dir.appendingPathComponent("duplicate.dcm").path)
        let database = try DatabaseManager(connectionString: "filesystem://")
        await fails("duplicate SOP Instance UID") { try await database.initialize(storage: storage) }
        let count = await database.instanceCount
        XCTAssertEqual(count, 0)
        await fails("initialization is incomplete") { _ = try await database.queryForFind(queryDataset: self.query(), level: .image) }
    }

    func testCorruptAndUnreadableFilesPreventCompleteIndex() async throws {
        for unreadable in [false, true] {
            let dir = directory(); defer { try? FileManager.default.removeItem(at: dir) }
            let storage = try StorageManager(dataDirectory: dir.path)
            _ = try await store(storage)
            let bad = dir.appendingPathComponent("bad.dcm")
            try Data("not a DICOM file".utf8).write(to: bad)
            if unreadable { try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: bad.path) }
            let database = try DatabaseManager(connectionString: "filesystem://")
            await fails(unreadable ? "unreadable" : "Not a Part 10") { try await database.initialize(storage: storage) }
            let count = await database.instanceCount
            XCTAssertEqual(count, 0)
        }
    }

    func testMissingIndexedFileMakesFindAndRetrieveFailVisibly() async throws {
        let dir = directory(); defer { try? FileManager.default.removeItem(at: dir) }
        let storage = try StorageManager(dataDirectory: dir.path)
        let saved = try await store(storage)
        let database = try DatabaseManager(connectionString: "filesystem://")
        try await database.initialize(storage: storage)
        try FileManager.default.removeItem(atPath: saved.filePath)
        await fails("missing or unreadable") { _ = try await database.queryForFind(queryDataset: self.query(), level: .image) }
        await fails("missing or unreadable") { _ = try await database.queryForRetrieve(queryDataset: self.query(), level: .image) }
    }

    func testSymlinkRootAndDescendantsRefusedWithoutOutsideTraversal() async throws {
        let dir = directory(), outside = directory(), link = directory()
        defer { for url in [link, dir, outside] { try? FileManager.default.removeItem(at: url) } }
        let storage = try StorageManager(dataDirectory: dir.path)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: outside)
        XCTAssertThrowsError(try StorageManager(dataDirectory: link.path))
        try FileManager.default.createSymbolicLink(at: dir.appendingPathComponent("escape"), withDestinationURL: outside)
        await fails("symbolic link") { _ = try await storage.scanForIndex() }
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: outside.path), [])
    }

    func testDirectoryBecomingSymlinkAfterIndexIsRefused() async throws {
        let dir = directory(), moved = directory()
        defer { try? FileManager.default.removeItem(at: dir); try? FileManager.default.removeItem(at: moved) }
        let storage = try StorageManager(dataDirectory: dir.path)
        let saved = try await store(storage)
        let database = try DatabaseManager(connectionString: "filesystem://")
        try await database.initialize(storage: storage)
        let parent = URL(fileURLWithPath: saved.filePath).deletingLastPathComponent()
        try FileManager.default.moveItem(at: parent, to: moved)
        try FileManager.default.createSymbolicLink(at: parent, withDestinationURL: moved)
        await fails("symbolic link") { _ = try await database.queryForRetrieve(queryDataset: self.query(), level: .image) }
        await fails("symbolic link") { _ = try await self.store(storage) }
    }

    func testExclusiveLockAndInterruptedTemporaryFiles() async throws {
        let dir = directory(); defer { try? FileManager.default.removeItem(at: dir) }
        let first = try StorageManager(dataDirectory: dir.path), second = try StorageManager(dataDirectory: dir.path)
        try await first.acquireExclusiveAccess()
        await fails("already in use") { try await second.acquireExclusiveAccess() }
        try Data("interrupted incomplete upload".utf8).write(to: dir.appendingPathComponent(".dicomkit-upload-test.tmp"))
        let records = try await first.scanForIndex()
        XCTAssertEqual(records.count, 0)
        await first.releaseExclusiveAccess()
        try await second.acquireExclusiveAccess()
        await second.releaseExclusiveAccess()
    }

    func testCommandDatasetIdentityMismatchIsNeverPublished() async throws {
        let dir = directory(); defer { try? FileManager.default.removeItem(at: dir) }
        let storage = try StorageManager(dataDirectory: dir.path)
        await fails("conflicting SOP") {
            _ = try await storage.storeReceived(dataSetData: ServerProtocol.encodeDataSet(self.dataset(), transferSyntaxUID: self.explicitLE),
                sopClassUID: self.sopClass, sopInstanceUID: "1.2.999", transferSyntaxUID: self.explicitLE, serverAETitle: "SCP", callingAETitle: nil)
        }
        let records = try await storage.scanForIndex()
        XCTAssertEqual(records.count, 0)
    }

    func testNativeSyntaxesAndNestedSequenceEnvelopesRemainAccepted() async throws {
        for syntax in ["1.2.840.10008.1.2", explicitLE, "1.2.840.10008.1.2.2"] {
            let dir = directory(); defer { try? FileManager.default.removeItem(at: dir) }
            let storage = try StorageManager(dataDirectory: dir.path)
            var ds = dataset(), item = DataSet()
            item.setString("Requested", for: .requestedProcedureID, vr: .SH)
            ds.setSequence([SequenceItem(elements: item.allElements)], for: .requestAttributesSequence)
            let payload = ServerProtocol.encodeDataSet(ds, transferSyntaxUID: syntax)
            let saved = try await storage.storeReceived(dataSetData: payload, sopClassUID: sopClass, sopInstanceUID: instance,
                transferSyntaxUID: syntax, serverAETitle: "SCP", callingAETitle: nil)
            let bytes = try Data(contentsOf: URL(fileURLWithPath: saved.filePath))
            XCTAssertEqual(try ServerProtocol.readStoredFile(bytes).dataSetData, payload)
            XCTAssertThrowsError(try StoredFileEnvelope.validate(bytes + Data([0]), transferSyntaxUID: syntax))
            XCTAssertThrowsError(try StoredFileEnvelope.validate(Data(bytes.dropLast()), transferSyntaxUID: syntax))
            let records = try await storage.scanForIndex()
            XCTAssertEqual(records.count, 1)
        }
    }

    func testUndefinedUNUsesImplicitLittleEndianItemsEvenInsideBigEndian() throws {
        let syntax = "1.2.840.10008.1.2.2"
        let meta = ServerProtocol.fileMetaInformation(sopClassUID: sopClass, sopInstanceUID: instance,
            transferSyntaxUID: syntax, serverAETitle: "SCP", callingAETitle: nil)
        // PS3.5 6.2.2: an undefined-length UN is internally Implicit VR Little Endian.
        let unknown = Data([0,0x11,0x10,0x10,0x55,0x4e,0,0,0xff,0xff,0xff,0xff,
                            0xfe,0xff,0,0xe0,10,0,0,0,0x10,0,0x20,0,2,0,0,0,0x41,0x42,
                            0xfe,0xff,0xdd,0xe0,0,0,0,0])
        let file = ServerProtocol.partTenHeader(fileMeta: meta)
            + ServerProtocol.encodeDataSet(dataset(), transferSyntaxUID: syntax) + unknown
        XCTAssertNoThrow(try StoredFileEnvelope.validate(file, transferSyntaxUID: syntax))
        XCTAssertThrowsError(try StoredFileEnvelope.validate(Data(file.dropLast()), transferSyntaxUID: syntax))
    }

    func testEnvelopeRejectsDuplicateTagsAndDamagedSequenceItems() throws {
        let payload = ServerProtocol.encodeDataSet(dataset(), transferSyntaxUID: explicitLE)
        let meta = ServerProtocol.fileMetaInformation(sopClassUID: sopClass, sopInstanceUID: instance,
            transferSyntaxUID: explicitLE, serverAETitle: "SCP", callingAETitle: nil)
        let header = ServerProtocol.partTenHeader(fileMeta: meta)
        XCTAssertThrowsError(try StoredFileEnvelope.validate(header + payload + payload, transferSyntaxUID: explicitLE))
        // Request Attributes Sequence, undefined length, missing Item/Sequence delimiters.
        let damaged = Data([0x40,0,0x75,0x02,0x53,0x51,0,0,0xff,0xff,0xff,0xff,
                            0xfe,0xff,0,0xe0,0xff,0xff,0xff,0xff])
        XCTAssertThrowsError(try StoredFileEnvelope.validate(header + payload + damaged, transferSyntaxUID: explicitLE))
    }

    func testEncapsulatedEnvelopeRetainsBytesAndRequiresCompleteDelimiter() async throws {
        let dir = directory(); defer { try? FileManager.default.removeItem(at: dir) }
        let syntax = "1.2.840.10008.1.2.4.50"
        // Synthetic JPEG envelope exercises storage only; compressed image decoding is not asserted.
        let pixels = Data([0xe0,0x7f,0x10,0,0x4f,0x42,0,0,0xff,0xff,0xff,0xff,
                           0xfe,0xff,0,0xe0,0,0,0,0,
                           0xfe,0xff,0,0xe0,2,0,0,0,0xff,0xd9,
                           0xfe,0xff,0xdd,0xe0,0,0,0,0])
        let payload = ServerProtocol.encodeDataSet(dataset(), transferSyntaxUID: explicitLE) + pixels
        let storage = try StorageManager(dataDirectory: dir.path)
        let saved = try await storage.storeReceived(dataSetData: payload, sopClassUID: sopClass, sopInstanceUID: instance,
            transferSyntaxUID: syntax, serverAETitle: "SCP", callingAETitle: nil)
        let bytes = try Data(contentsOf: URL(fileURLWithPath: saved.filePath))
        XCTAssertEqual(try ServerProtocol.readStoredFile(bytes).dataSetData, payload)
        XCTAssertThrowsError(try StoredFileEnvelope.validate(Data(bytes.dropLast(8)), transferSyntaxUID: syntax))
        XCTAssertThrowsError(try StoredFileEnvelope.validate(bytes + Data([0]), transferSyntaxUID: syntax))
    }

    #if canImport(Compression)
    func testDeflatedEnvelopeRetainsBytesAndRejectsTruncatedOrTrailingStream() async throws {
        let dir = directory(); defer { try? FileManager.default.removeItem(at: dir) }
        let syntax = "1.2.840.10008.1.2.1.99"
        let payload = try XCTUnwrap(ServerProtocol.encodeDataSet(dataset(), transferSyntaxUID: explicitLE).deflateCompressed())
        let storage = try StorageManager(dataDirectory: dir.path)
        let saved = try await storage.storeReceived(dataSetData: payload, sopClassUID: sopClass, sopInstanceUID: instance,
            transferSyntaxUID: syntax, serverAETitle: "SCP", callingAETitle: nil)
        let bytes = try Data(contentsOf: URL(fileURLWithPath: saved.filePath))
        XCTAssertEqual(try ServerProtocol.readStoredFile(bytes).dataSetData, payload)
        XCTAssertThrowsError(try StoredFileEnvelope.validate(Data(bytes.dropLast()), transferSyntaxUID: syntax))
        XCTAssertThrowsError(try StoredFileEnvelope.validate(bytes + Data([0]), transferSyntaxUID: syntax))
    }
    #endif
}
