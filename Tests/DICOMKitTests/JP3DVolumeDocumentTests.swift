import Foundation
import Testing
@testable import DICOMKit
import DICOMCore

/// Tests for JP3DVolumeDocument (Milestone 4.3) and DICOMKit+Volume (Milestone 4.4).
@Suite("JP3DVolumeDocument Tests")
struct JP3DVolumeDocumentTests {

    // MARK: - Helpers

    private func makeGrayscaleFile(
        rows: Int,
        columns: Int,
        sliceIndex: Int,
        seriesUID: String,
        studyUID: String,
        photometric: String = "MONOCHROME2"
    ) throws -> DICOMFile {
        let bytesPerPixel = 2
        var pixelData = Data(capacity: rows * columns * bytesPerPixel)
        for row in 0..<rows {
            for col in 0..<columns {
                var v = UInt16((sliceIndex * 256 + row * 16 + col) & 0x0FFF).littleEndian
                pixelData.append(Data(bytes: &v, count: 2))
            }
        }

        var ds = DataSet()
        ds.setUInt16(UInt16(rows), for: .rows)
        ds.setUInt16(UInt16(columns), for: .columns)
        ds.setUInt16(16, for: .bitsAllocated)
        ds.setUInt16(12, for: .bitsStored)
        ds.setUInt16(11, for: .highBit)
        ds.setUInt16(0, for: .pixelRepresentation)
        ds.setUInt16(1, for: .samplesPerPixel)
        ds.setString(photometric, for: .photometricInterpretation, vr: .CS)
        ds.setString("CT", for: .modality, vr: .CS)
        ds.setString(studyUID, for: .studyInstanceUID, vr: .UI)
        ds.setString(seriesUID, for: .seriesInstanceUID, vr: .UI)
        ds.setString(UIDGenerator.generateUID().value, for: .sopInstanceUID, vr: .UI)
        ds.setInt(sliceIndex + 1, for: .instanceNumber, vr: .IS)
        ds.setString("1.2.840.10008.5.1.4.1.1.2", for: .sopClassUID, vr: .UI)
        ds.setString("PATIENT", for: .patientName, vr: .PN)
        ds.setString("ID001", for: .patientID, vr: .LO)

        // Spatial position for sorting
        let z = Double(sliceIndex) * 2.5
        ds.setString("0.0\\0.0\\\(z)", for: .imagePositionPatient, vr: .DS)
        ds.setString(String(z), for: .sliceLocation, vr: .DS)
        ds.setString("0.8\\0.8", for: .pixelSpacing, vr: .DS)
        ds.setString("2.5", for: .sliceThickness, vr: .DS)

        ds[.pixelData] = DataElement.data(tag: .pixelData, vr: .OW, data: pixelData)

        return try DICOMFile.create(
            dataSet: ds,
            sopClassUID: "1.2.840.10008.5.1.4.1.1.2",
            sopInstanceUID: ds.string(for: .sopInstanceUID)!,
            transferSyntaxUID: TransferSyntax.explicitVRLittleEndian.uid
        )
    }

    private func makeSeries(slices: Int = 4, rows: Int = 16, columns: Int = 16) throws -> [DICOMFile] {
        let studyUID = UIDGenerator.generateUID().value
        let seriesUID = UIDGenerator.generateUID().value
        return try (0..<slices).map { i in
            try makeGrayscaleFile(rows: rows, columns: columns, sliceIndex: i, seriesUID: seriesUID, studyUID: studyUID)
        }
    }

    // MARK: - SOP Class / Detection

    @Test("JP3DVolumeDocument SOP class UID is private experimental")
    func test_sopClassUID_isPrivate() {
        let uid = JP3DVolumeDocument.sopClassUID
        #expect(uid == "1.2.826.0.1.3680043.10.511.10")
        #expect(uid.hasPrefix("1.2.826.0.1.3680043")) // Raster-Lab OID root
    }

    @Test("JP3DVolumeDocument MIME type is application/x-jp3d")
    func test_mimeType() {
        #expect(JP3DVolumeDocument.mimeType == "application/x-jp3d")
    }

    @Test("isJP3DVolumeDocument returns false for regular DICOM files")
    func test_detection_regularFile() throws {
        let series = try makeSeries()
        #expect(!JP3DVolumeDocument.isJP3DVolumeDocument(series[0]))
    }

    // MARK: - Validation & Fail-Closed Deferral (pending SwiftJ2K 12.2.0 / SwiftJ2K3D)

    @Test("encode empty series throws BridgeError.emptySeries")
    func test_encode_emptySeriesThrows() async {
        do {
            _ = try await JP3DVolumeDocument.encode(series: [])
            Issue.record("Expected encode to throw but it succeeded")
        } catch is JP3DVolumeBridge.BridgeError {
            // Expected
        } catch {
            Issue.record("Expected BridgeError but got \(error)")
        }
    }

    @Test("encode refuses a series whose slices disagree on Photometric Interpretation")
    func test_encode_mixedPhotometricThrows() async throws {
        let studyUID = UIDGenerator.generateUID().value
        let seriesUID = UIDGenerator.generateUID().value
        let series = try (0..<2).map { i in
            try makeGrayscaleFile(rows: 8, columns: 8, sliceIndex: i, seriesUID: seriesUID,
                                  studyUID: studyUID, photometric: i == 0 ? "MONOCHROME2" : "MONOCHROME1")
        }
        await #expect(throws: DICOMError.self) {
            _ = try await JP3DVolumeDocument.encode(series: series, compressionMode: .lossless)
        }
    }

    @Test("decode from non-JP3D document throws DICOMError")
    func test_decode_nonJP3DThrows() async throws {
        let series = try makeSeries(slices: 2)
        // Feed a regular DICOM file, not a JP3D document
        do {
            _ = try await JP3DVolumeDocument.decode(from: series[0])
            Issue.record("Expected decode to throw but it succeeded")
        } catch is DICOMError {
            // Expected
        } catch {
            Issue.record("Expected DICOMError but got \(error)")
        }
    }

    @Test("encode fails closed with SwiftJ2K 12.2.0 deferral across all compression modes")
    func test_encode_failsClosedWhileDeferred() async throws {
        let series = try makeSeries(slices: 4, rows: 8, columns: 8)
        for mode: JP3DCodec.CompressionMode in [.lossless, .lossy(psnr: 40.0), .losslessHTJ2K] {
            do {
                _ = try await JP3DVolumeDocument.encode(series: series, compressionMode: mode)
                Issue.record("Expected JP3DVolumeDocument.encode to fail closed while deferred")
            } catch let DICOMError.unsupportedTransferSyntax(reason) {
                #expect(reason.contains("SwiftJ2K 12.2.0"))
            }
        }
    }
}

/// Tests for DICOMVolume struct and DICOMFile.openVolume (Milestone 4.4).
@Suite("DICOMVolume Tests")
struct DICOMVolumeTests {

    // MARK: - DICOMVolume struct

    @Test("DICOMVolume slice(at:) returns correct slice data")
    func test_sliceAt_correctData() {
        let width = 4, height = 4, depth = 3
        let bytesPerSlice = width * height * 2
        var pixels = Data(capacity: bytesPerSlice * depth)
        for i in 0..<depth {
            pixels.append(Data(repeating: UInt8(i + 1), count: bytesPerSlice))
        }

        let vol = DICOMVolume(
            width: width, height: height, depth: depth,
            bitsAllocated: 16, bitsStored: 16, isSigned: false,
            pixelData: pixels
        )

        let s0 = vol.slice(at: 0)!
        let s1 = vol.slice(at: 1)!
        let s2 = vol.slice(at: 2)!
        #expect(s0 == Data(repeating: 1, count: bytesPerSlice))
        #expect(s1 == Data(repeating: 2, count: bytesPerSlice))
        #expect(s2 == Data(repeating: 3, count: bytesPerSlice))
    }

    @Test("DICOMVolume slice(at:) returns nil for out-of-bounds index")
    func test_sliceAt_outOfBounds() {
        let vol = DICOMVolume(
            width: 4, height: 4, depth: 2,
            bitsAllocated: 16, bitsStored: 16, isSigned: false,
            pixelData: Data(count: 4 * 4 * 2 * 2)
        )
        #expect(vol.slice(at: -1) == nil)
        #expect(vol.slice(at: 2) == nil)
    }

    @Test("DICOMVolume voxel(x:y:z:) returns correct 16-bit unsigned value")
    func test_voxel_unsigned16() {
        let width = 2, height = 2, depth = 2
        // Lay out: voxel(0,0,0)=100, voxel(1,0,0)=200, ...
        var pixels = Data()
        for v: UInt16 in [100, 200, 300, 400, 500, 600, 700, 800] {
            var le = v.littleEndian
            pixels.append(Data(bytes: &le, count: 2))
        }
        let vol = DICOMVolume(
            width: width, height: height, depth: depth,
            bitsAllocated: 16, bitsStored: 16, isSigned: false,
            pixelData: pixels
        )
        #expect(vol.voxel(x: 0, y: 0, z: 0) == 100)
        #expect(vol.voxel(x: 1, y: 0, z: 0) == 200)
        #expect(vol.voxel(x: 0, y: 0, z: 1) == 500)
    }

    @Test("DICOMVolume voxel(x:y:z:) returns nil for out-of-bounds coordinates")
    func test_voxel_outOfBounds() {
        let vol = DICOMVolume(
            width: 2, height: 2, depth: 2,
            bitsAllocated: 16, bitsStored: 16, isSigned: false,
            pixelData: Data(count: 2 * 2 * 2 * 2)
        )
        #expect(vol.voxel(x: -1, y: 0, z: 0) == nil)
        #expect(vol.voxel(x: 2, y: 0, z: 0) == nil)
        #expect(vol.voxel(x: 0, y: 0, z: 2) == nil)
    }

    @Test("DICOMVolume bytesPerSlice is correct")
    func test_bytesPerSlice() {
        let vol = DICOMVolume(
            width: 512, height: 512, depth: 10,
            bitsAllocated: 16, bitsStored: 12, isSigned: false,
            pixelData: Data(count: 512 * 512 * 2 * 10)
        )
        #expect(vol.bytesPerSlice == 512 * 512 * 2)
        #expect(vol.voxelCount == 512 * 512 * 10)
    }

    // MARK: - openVolume from single multi-frame file

    @Test("openVolume from multi-frame DICOM file returns correct dimensions")
    func test_openVolume_multiframe() async throws {
        let rows = 16, columns = 16, frames = 8
        let bytesPerFrame = rows * columns * 2
        var pixelData = Data(capacity: bytesPerFrame * frames)
        for f in 0..<frames {
            pixelData.append(Data(repeating: UInt8(f + 1), count: bytesPerFrame))
        }

        var ds = DataSet()
        ds.setUInt16(UInt16(rows), for: .rows)
        ds.setUInt16(UInt16(columns), for: .columns)
        ds.setUInt16(16, for: .bitsAllocated)
        ds.setUInt16(12, for: .bitsStored)
        ds.setUInt16(11, for: .highBit)
        ds.setUInt16(0, for: .pixelRepresentation)
        ds.setUInt16(1, for: .samplesPerPixel)
        ds.setString("MONOCHROME2", for: .photometricInterpretation, vr: .CS)
        ds.setString("CT", for: .modality, vr: .CS)
        ds.setInt(frames, for: .numberOfFrames, vr: .IS)
        ds.setString(UIDGenerator.generateUID().value, for: .studyInstanceUID, vr: .UI)
        ds.setString(UIDGenerator.generateUID().value, for: .seriesInstanceUID, vr: .UI)
        ds.setString(UIDGenerator.generateUID().value, for: .sopInstanceUID, vr: .UI)
        ds.setString("1.2.840.10008.5.1.4.1.1.2", for: .sopClassUID, vr: .UI)
        ds.setString("0.8\\0.8", for: .pixelSpacing, vr: .DS)
        ds.setString("2.5", for: .sliceThickness, vr: .DS)
        ds[.pixelData] = DataElement.data(tag: .pixelData, vr: .OW, data: pixelData)

        let dicomFile = try DICOMFile.create(
            dataSet: ds,
            sopClassUID: "1.2.840.10008.5.1.4.1.1.2",
            sopInstanceUID: ds.string(for: .sopInstanceUID)!,
            transferSyntaxUID: TransferSyntax.explicitVRLittleEndian.uid
        )

        // Write to temp file then re-open via openVolume
        let tmpURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("test_multiframe_\(UUID().uuidString).dcm")
        defer { try? FileManager.default.removeItem(at: tmpURL) }
        let fileData = try dicomFile.write()
        try fileData.write(to: tmpURL)

        let volume = try await DICOMFile.openVolume(from: tmpURL)
        #expect(volume.width == columns)
        #expect(volume.height == rows)
        #expect(volume.depth == frames)
        #expect(volume.modality == "CT")
        #expect(volume.pixelData.count == bytesPerFrame * frames)
    }

    // MARK: - openVolume from JP3D document

    @Test("openVolume from JP3D encapsulated document returns correct dimensions")
    func test_openVolume_jp3dDocument() async throws {
        // Build a series, encode to JP3D, write to temp, open via openVolume
        let studyUID = UIDGenerator.generateUID().value
        let seriesUID = UIDGenerator.generateUID().value
        let rows = 16, columns = 16, slices = 4

        let series = try (0..<slices).map { i -> DICOMFile in
            let bytesPerPixel = 2
            var px = Data(capacity: rows * columns * bytesPerPixel)
            for r in 0..<rows {
                for c in 0..<columns {
                    var v = UInt16((i * 256 + r * 16 + c) & 0x0FFF).littleEndian
                    px.append(Data(bytes: &v, count: 2))
                }
            }
            var ds = DataSet()
            ds.setUInt16(UInt16(rows), for: .rows)
            ds.setUInt16(UInt16(columns), for: .columns)
            ds.setUInt16(16, for: .bitsAllocated)
            ds.setUInt16(12, for: .bitsStored)
            ds.setUInt16(11, for: .highBit)
            ds.setUInt16(0, for: .pixelRepresentation)
            ds.setUInt16(1, for: .samplesPerPixel)
            ds.setString("MONOCHROME2", for: .photometricInterpretation, vr: .CS)
            ds.setString("CT", for: .modality, vr: .CS)
            ds.setString(studyUID, for: .studyInstanceUID, vr: .UI)
            ds.setString(seriesUID, for: .seriesInstanceUID, vr: .UI)
            ds.setString(UIDGenerator.generateUID().value, for: .sopInstanceUID, vr: .UI)
            ds.setString("1.2.840.10008.5.1.4.1.1.2", for: .sopClassUID, vr: .UI)
            ds.setString("0.0\\0.0\\\(Double(i) * 2.5)", for: .imagePositionPatient, vr: .DS)
            ds.setString(String(Double(i) * 2.5), for: .sliceLocation, vr: .DS)
            ds.setString("0.8\\0.8", for: .pixelSpacing, vr: .DS)
            ds.setString("2.5", for: .sliceThickness, vr: .DS)
            ds.setInt(i + 1, for: .instanceNumber, vr: .IS)
            ds[.pixelData] = DataElement.data(tag: .pixelData, vr: .OW, data: px)
            return try DICOMFile.create(
                dataSet: ds,
                sopClassUID: "1.2.840.10008.5.1.4.1.1.2",
                sopInstanceUID: ds.string(for: .sopInstanceUID)!,
                transferSyntaxUID: TransferSyntax.explicitVRLittleEndian.uid
            )
        }

        do {
            _ = try await JP3DVolumeDocument.encode(series: series, compressionMode: .lossless)
            Issue.record("Expected JP3DVolumeDocument.encode to fail closed while deferred")
        } catch let DICOMError.unsupportedTransferSyntax(reason) {
            #expect(reason.contains("SwiftJ2K 12.2.0"))
        }
    }

    @Test("openVolume throws for non-existent path")
    func test_openVolume_nonExistentPath() async {
        let url = URL(fileURLWithPath: "/tmp/does_not_exist_\(UUID().uuidString).dcm")
        do {
            _ = try await DICOMFile.openVolume(from: url)
            Issue.record("Expected openVolume to throw but it succeeded")
        } catch is DICOMError {
            // Expected
        } catch {
            Issue.record("Expected DICOMError but got \(error)")
        }
    }
}
