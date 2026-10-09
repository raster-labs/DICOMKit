// NEMA-verified: 2026a, checked 2026-10-01 — PS3.10 2026a Table 7.1-1 (0002,0002)/(0002,0003) equal the data set's (0008,0016)/(0008,0018); PS3.15 2026a Table E.1-1 (0002,0003) U; PS3.3 2026a Table F.3-1 (Basic Directory IOD has no SOP Common Module)
//
// D175 (root cause) and the DICOMKit callers D137 (UIDManager), D162 (Anonymizer), D165
// (ImageConverter): the File Meta Media Storage SOP Class / Instance UIDs written by
// `DICOMFile.create` and by the File-Meta-preserving paths agree with the data set.

import XCTest
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
@testable import DICOMKit
import DICOMCore

final class FileMetaMediaStorageUIDTests: XCTestCase {

    private let ctImageStorage = "1.2.840.10008.5.1.4.1.1.2"
    private let mrImageStorage = "1.2.840.10008.5.1.4.1.1.4"
    private let secondaryCapture = "1.2.840.10008.5.1.4.1.1.7"
    private let mediaStorageDirectoryStorage = "1.2.840.10008.1.3.10"

    private func meta(_ file: DICOMFile) -> (cls: String?, inst: String?) {
        (file.fileMetaInformation.string(for: .mediaStorageSOPClassUID),
         file.fileMetaInformation.string(for: .mediaStorageSOPInstanceUID))
    }

    private func assertAgrees(_ file: DICOMFile, file line: UInt = #line) {
        XCTAssertNotNil(file.dataSet.string(for: .sopClassUID), line: line)
        XCTAssertNotNil(file.dataSet.string(for: .sopInstanceUID), line: line)
        XCTAssertEqual(meta(file).cls, file.dataSet.string(for: .sopClassUID), "(0002,0002) ≠ (0008,0016)", line: line)
        XCTAssertEqual(meta(file).inst, file.dataSet.string(for: .sopInstanceUID), "(0002,0003) ≠ (0008,0018)", line: line)
    }

    private func ctDataSet(instance: String = "1.2.826.0.1.3680043.10.511.99.1") -> DataSet {
        var ds = DataSet()
        ds.setString(ctImageStorage, for: .sopClassUID, vr: .UI)
        ds.setString(instance, for: .sopInstanceUID, vr: .UI)
        ds.setString("DOE^JOHN", for: .patientName, vr: .PN)
        ds.setString("1.2.826.0.1.3680043.10.511.99.2", for: .studyInstanceUID, vr: .UI)
        ds.setString("1.2.826.0.1.3680043.10.511.99.3", for: .seriesInstanceUID, vr: .UI)
        return ds
    }

    // MARK: - D175: DICOMFile.create

    /// Arguments omitted: both UIDs come from the data set (formerly SC + a fresh UID).
    func test_create_argumentsOmitted_usesDataSetUIDs() {
        let file = DICOMFile.create(dataSet: ctDataSet())
        XCTAssertEqual(meta(file).cls, ctImageStorage)
        XCTAssertEqual(meta(file).inst, "1.2.826.0.1.3680043.10.511.99.1")
        assertAgrees(file)
    }

    /// Only the transfer syntax given (the D112 / D165 call shape).
    func test_create_onlyTransferSyntax_usesDataSetUIDs() {
        let file = DICOMFile.create(dataSet: ctDataSet(), transferSyntaxUID: "1.2.840.10008.1.2")
        XCTAssertEqual(meta(file).cls, ctImageStorage)
        XCTAssertEqual(file.transferSyntaxUID, "1.2.840.10008.1.2")
        assertAgrees(file)
    }

    /// Arguments equal to the data set: unchanged behaviour.
    func test_create_matchingArguments() {
        let file = DICOMFile.create(dataSet: ctDataSet(), sopClassUID: ctImageStorage,
                                    sopInstanceUID: "1.2.826.0.1.3680043.10.511.99.1")
        assertAgrees(file)
    }

    /// Arguments that differ from the data set: the data set is authoritative, so the File Meta
    /// still describes the data set placed in the file (PS3.10 Table 7.1-1).
    func test_create_conflictingArguments_dataSetWins() {
        let file = DICOMFile.create(dataSet: ctDataSet(), sopClassUID: mrImageStorage,
                                    sopInstanceUID: "1.2.826.0.1.3680043.10.511.99.777")
        XCTAssertEqual(meta(file).cls, ctImageStorage)
        XCTAssertEqual(meta(file).inst, "1.2.826.0.1.3680043.10.511.99.1")
        XCTAssertEqual(file.dataSet.string(for: .sopClassUID), ctImageStorage)
        XCTAssertEqual(file.dataSet.string(for: .sopInstanceUID), "1.2.826.0.1.3680043.10.511.99.1")
    }

    /// Data set without SOP UIDs, arguments given: the arguments are used and written into the
    /// data set as well.
    func test_create_dataSetWithoutUIDs_argumentsAreWrittenToBoth() {
        var ds = DataSet()
        ds.setString("DOE^JANE", for: .patientName, vr: .PN)
        let file = DICOMFile.create(dataSet: ds, sopClassUID: mrImageStorage,
                                    sopInstanceUID: "1.2.826.0.1.3680043.10.511.99.5")
        XCTAssertEqual(meta(file).cls, mrImageStorage)
        XCTAssertEqual(meta(file).inst, "1.2.826.0.1.3680043.10.511.99.5")
        assertAgrees(file)
    }

    /// Data set without SOP UIDs and no arguments: Secondary Capture and a generated UID, the
    /// same values in the File Meta and the data set.
    func test_create_nothingGiven_secondaryCaptureAndGeneratedUIDInBoth() {
        let file = DICOMFile.create(dataSet: DataSet())
        XCTAssertEqual(meta(file).cls, secondaryCapture)
        XCTAssertNotNil(meta(file).inst)
        XCTAssertNotNil(DICOMUniqueIdentifier.parse(meta(file).inst ?? ""))
        assertAgrees(file)
    }

    /// Only one of the two in the data set: each UID resolves independently.
    func test_create_onlyClassInDataSet_instanceFromArgument() {
        var ds = DataSet()
        ds.setString(ctImageStorage, for: .sopClassUID, vr: .UI)
        let file = DICOMFile.create(dataSet: ds, sopClassUID: mrImageStorage,
                                    sopInstanceUID: "1.2.826.0.1.3680043.10.511.99.6")
        XCTAssertEqual(meta(file).cls, ctImageStorage)
        XCTAssertEqual(meta(file).inst, "1.2.826.0.1.3680043.10.511.99.6")
        assertAgrees(file)
    }

    /// An empty (0008,0018) counts as absent.
    func test_create_emptyDataSetInstanceUID_isReplaced() {
        var ds = ctDataSet()
        ds.setString("", for: .sopInstanceUID, vr: .UI)
        let file = DICOMFile.create(dataSet: ds)
        XCTAssertFalse((meta(file).inst ?? "").isEmpty)
        assertAgrees(file)
    }

    /// A Basic Directory (DICOMDIR) data set has no SOP Common Module (PS3.3 Table F.3-1):
    /// nothing is added to it.
    func test_create_dicomdir_dataSetNotModified() {
        var ds = DataSet()
        ds.setString("EXAMPLE", for: Tag(group: 0x0004, element: 0x1130), vr: .CS) // File-set ID
        let file = DICOMFile.create(dataSet: ds, sopClassUID: mediaStorageDirectoryStorage,
                                    sopInstanceUID: "1.2.826.0.1.3680043.10.511.99.7")
        XCTAssertEqual(meta(file).cls, mediaStorageDirectoryStorage)
        XCTAssertEqual(meta(file).inst, "1.2.826.0.1.3680043.10.511.99.7")
        XCTAssertNil(file.dataSet[.sopClassUID])
        XCTAssertNil(file.dataSet[.sopInstanceUID])
        XCTAssertEqual(file.dataSet.count, 1)
    }

    /// Source compatibility: a non-optional String variable still binds to `sopClassUID:`.
    func test_create_nonOptionalStringArgumentStillCompiles() {
        let cls: String = ctImageStorage
        let file = DICOMFile.create(dataSet: DataSet(), sopClassUID: cls)
        XCTAssertEqual(meta(file).cls, ctImageStorage)
        assertAgrees(file)
    }

    /// Bytes written and read back agree, and (0002,0000) is the File Meta byte length.
    func test_create_roundTrip_agreesAndGroupLengthCorrect() throws {
        let file = DICOMFile.create(dataSet: ctDataSet())
        let read = try DICOMFile.read(from: try file.write())
        assertAgrees(read)
        let groupLength = read.fileMetaInformation.uint32(for: .fileMetaInformationGroupLength)
        var others = read.fileMetaInformation
        others.remove(tag: .fileMetaInformationGroupLength)
        XCTAssertEqual(groupLength.map(Int.init), others.write(using: DICOMWriter(byteOrder: .littleEndian, explicitVR: true)).count)
    }

    // MARK: - synchronizingMediaStorageUIDs()

    func test_synchronizing_fixesMismatchAndRecomputesGroupLength() throws {
        let original = DICOMFile.create(dataSet: ctDataSet())
        var ds = original.dataSet
        ds.setString("1.2.826.0.1.3680043.10.511.99.12345678901234567890", for: .sopInstanceUID, vr: .UI)
        let stale = DICOMFile(fileMetaInformation: original.fileMetaInformation, dataSet: ds)
        XCTAssertNotEqual(meta(stale).inst, ds.string(for: .sopInstanceUID))

        let synced = stale.synchronizingMediaStorageUIDs()
        assertAgrees(synced)
        XCTAssertEqual(synced.fileMetaInformation.string(for: .implementationClassUID), DICOMFile.implementationClassUID)
        var others = synced.fileMetaInformation
        others.remove(tag: .fileMetaInformationGroupLength)
        XCTAssertEqual(synced.fileMetaInformation.uint32(for: .fileMetaInformationGroupLength).map(Int.init),
                       others.write(using: DICOMWriter(byteOrder: .littleEndian, explicitVR: true)).count)
        assertAgrees(try DICOMFile.read(from: try synced.write()))
    }

    func test_synchronizing_dataSetWithoutUIDs_keepsFileMeta() {
        var meta = DataSet()
        meta.setString(ctImageStorage, for: .mediaStorageSOPClassUID, vr: .UI)
        meta.setString("1.2.3.4", for: .mediaStorageSOPInstanceUID, vr: .UI)
        let file = DICOMFile(fileMetaInformation: meta, dataSet: DataSet())
        let synced = file.synchronizingMediaStorageUIDs()
        XCTAssertEqual(self.meta(synced).cls, ctImageStorage)
        XCTAssertEqual(self.meta(synced).inst, "1.2.3.4")
    }

    // MARK: - D137: UIDManager.regenerateData

    func test_uidManager_regenerate_fileMetaFollowsNewSOPInstanceUID() throws {
        let source = try DICOMFile.create(dataSet: ctDataSet()).write()
        var mappings: [String: String] = [:]
        let (data, _) = try UIDManager().regenerateData(
            source, root: nil, maintainRelationships: true, existingMappings: &mappings)
        let out = try DICOMFile.read(from: data)
        XCTAssertNotEqual(out.dataSet.string(for: .sopInstanceUID), "1.2.826.0.1.3680043.10.511.99.1")
        XCTAssertEqual(meta(out).cls, ctImageStorage)
        assertAgrees(out)
    }

    // MARK: - D162: Anonymizer

    func test_anonymizer_deidentify_fileMetaFollowsRegeneratedUID() throws {
        let source = DICOMFile.create(dataSet: ctDataSet())
        let (out, _, _) = Anonymizer(profile: .basic).deidentify(file: source)
        XCTAssertNotEqual(out.dataSet.string(for: .sopInstanceUID), "1.2.826.0.1.3680043.10.511.99.1")
        assertAgrees(out)
        assertAgrees(try DICOMFile.read(from: try out.write()))
    }

    func test_anonymizer_anonymize_regenerateUIDs_fileMetaFollows() throws {
        let source = DICOMFile.create(dataSet: ctDataSet())
        let (out, _) = try Anonymizer(profile: .basic, regenerateUIDs: true).anonymize(file: source, filePath: "x.dcm")
        XCTAssertNotEqual(out.dataSet.string(for: .sopInstanceUID), "1.2.826.0.1.3680043.10.511.99.1")
        assertAgrees(out)
        assertAgrees(try DICOMFile.read(from: try out.write()))
    }

    // MARK: - D165: ImageConverter

    func test_imageConverter_secondaryCapture_fileMetaEqualsDataSet() throws {
        let rgba: [UInt8] = [255, 0, 0, 255, 0, 255, 0, 255, 0, 0, 255, 255, 255, 255, 255, 255]
        let provider = CGDataProvider(data: Data(rgba) as CFData)!
        let image = CGImage(
            width: 2, height: 2, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: 8,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue),
            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("FileMetaMediaStorageUIDTests-\(UUID().uuidString).png")
        let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(dest, image, nil)
        XCTAssertTrue(CGImageDestinationFinalize(dest))
        defer { try? FileManager.default.removeItem(at: url) }

        let metadata = ImageConverter.Metadata(
            patientName: "DOE^John", patientID: "12345",
            studyUID: ImageConverter.generateUID(), seriesUID: ImageConverter.generateUID(),
            instanceNumber: 1)
        let bytes = try ImageConverter.secondaryCaptureData(imageURL: url, metadata: metadata, useExif: false)
        let out = try DICOMFile.read(from: bytes)
        XCTAssertEqual(meta(out).cls, secondaryCapture)
        assertAgrees(out)
    }
}
