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

    // MARK: - Encode

    @Test("encode produces a DICOM file with JP3D SOP class")
    func test_encode_sopClass() async throws {
        let series = try makeSeries()
        let doc = try await JP3DVolumeDocument.encode(series: series)

        let fmiSOP = doc.fileMetaInformation.string(for: .mediaStorageSOPClassUID)
        let dsSOP = doc.dataSet.string(for: .sopClassUID)
        #expect(fmiSOP == JP3DVolumeDocument.sopClassUID)
        #expect(dsSOP == JP3DVolumeDocument.sopClassUID)
    }

    @Test("encode is detected by isJP3DVolumeDocument")
    func test_encode_detectable() async throws {
        let series = try makeSeries()
        let doc = try await JP3DVolumeDocument.encode(series: series)
        #expect(JP3DVolumeDocument.isJP3DVolumeDocument(doc))
    }

    @Test("encode sets correct MIME type")
    func test_encode_mimeType() async throws {
        let series = try makeSeries()
        let doc = try await JP3DVolumeDocument.encode(series: series)
        let mime = doc.dataSet.string(for: .mimeTypeOfEncapsulatedDocument)
        #expect(mime == JP3DVolumeDocument.mimeType)
    }

    @Test("encode preserves patient and study metadata")
    func test_encode_preservesMetadata() async throws {
        let series = try makeSeries()
        let studyUID = series[0].dataSet.string(for: .studyInstanceUID)!
        let doc = try await JP3DVolumeDocument.encode(series: series)

        #expect(doc.dataSet.string(for: .patientName) == "PATIENT")
        #expect(doc.dataSet.string(for: .patientID) == "ID001")
        #expect(doc.dataSet.string(for: .studyInstanceUID) == studyUID)
    }

    @Test("encode produces encapsulated document element")
    func test_encode_hasPayload() async throws {
        let series = try makeSeries()
        let doc = try await JP3DVolumeDocument.encode(series: series)
        let payload = doc.dataSet[.encapsulatedDocument]?.valueData
        #expect(payload != nil)
        #expect((payload?.count ?? 0) > 8) // At least header bytes
    }

    @Test("encode writes every Type 1/2 attribute of the Encapsulated Document IOD modules")
    func test_encode_iodType1Type2Attributes() async throws {
        let series = try makeSeries()
        let ds = try await JP3DVolumeDocument.encode(series: series).dataSet

        // Type 2 (present, may be empty): Tables C.7-1, C.7-3, C.7-8, C.24-2
        for tag in [Tag.patientName, .patientID, .patientBirthDate, .patientSex,
                    .studyDate, .studyTime, .referringPhysicianName, .studyID, .accessionNumber,
                    .manufacturer, .contentDate, .contentTime, .acquisitionDateTime,
                    .documentTitle, .conceptNameCodeSequence] {
            #expect(ds[tag] != nil, "\(tag) must be present")
        }
        // Type 1 (present and non-empty): Tables C.7-3, C.24-1, C.8-24, C.24-2, C.12-1
        for tag in [Tag.studyInstanceUID, .modality, .seriesInstanceUID, .seriesNumber, .conversionType,
                    .instanceNumber, .burnedInAnnotation, .mimeTypeOfEncapsulatedDocument,
                    .encapsulatedDocument, .sopClassUID, .sopInstanceUID] {
            let element = ds[tag]
            #expect(element != nil && element!.length > 0, "\(tag) is Type 1")
        }
        #expect(ds.string(for: .modality) == "DOC")
        #expect(ds.string(for: .conversionType) == "WSD")
        #expect(ds[.acquisitionDateTime]?.vr == .DT)
        #expect(ds[.documentTitle]?.vr == .ST)
        #expect(ds[.conceptNameCodeSequence]?.vr == .SQ)

        // The sidecar carries Patient's Name / ID → Burned In Annotation YES (Table C.24-2).
        #expect(ds.string(for: .burnedInAnnotation) == "YES")

        // Source Instance Sequence (1C: derived from DICOM Instances): one Item per slice.
        let sources = ds.sequence(for: .sourceInstanceSequence) ?? []
        #expect(sources.count == series.count)
        #expect(sources.first?.string(for: .referencedSOPClassUID) == "1.2.840.10008.5.1.4.1.1.2")
        #expect(sources.first?.string(for: .referencedSOPInstanceUID) == series[0].dataSet.string(for: .sopInstanceUID))
    }

    @Test("encode with custom study/series/SOP UIDs uses provided UIDs")
    func test_encode_customUIDs() async throws {
        let series = try makeSeries()
        let customStudy = "1.2.3.4.5"
        let customSeries = "1.2.3.4.5.6"
        let customSOP = "1.2.3.4.5.6.7"

        let doc = try await JP3DVolumeDocument.encode(
            series: series,
            studyInstanceUID: customStudy,
            seriesInstanceUID: customSeries,
            sopInstanceUID: customSOP
        )

        #expect(doc.dataSet.string(for: .studyInstanceUID) == customStudy)
        #expect(doc.dataSet.string(for: .seriesInstanceUID) == customSeries)
        #expect(doc.dataSet.string(for: .sopInstanceUID) == customSOP)
    }

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

    // MARK: - Encode / Decode Round-Trip

    @Test("encode/decode round-trip preserves slice count")
    func test_roundTrip_sliceCount() async throws {
        let series = try makeSeries(slices: 4)
        let doc = try await JP3DVolumeDocument.encode(series: series, compressionMode: .lossless)
        let decoded = try await JP3DVolumeDocument.decode(from: doc)
        #expect(decoded.count == 4)
    }

    @Test("encode/decode round-trip preserves image dimensions")
    func test_roundTrip_dimensions() async throws {
        let series = try makeSeries(slices: 4, rows: 16, columns: 16)
        let doc = try await JP3DVolumeDocument.encode(series: series, compressionMode: .lossless)
        let decoded = try await JP3DVolumeDocument.decode(from: doc)

        guard let first = decoded.first else {
            Issue.record("No decoded slices")
            return
        }
        #expect(first.dataSet.uint16(for: .rows) == 16)
        #expect(first.dataSet.uint16(for: .columns) == 16)
    }

    @Test("encode/decode round-trip preserves lossless pixel values")
    func test_roundTrip_losslessPixels() async throws {
        let series = try makeSeries(slices: 4, rows: 8, columns: 8)
        let doc = try await JP3DVolumeDocument.encode(series: series, compressionMode: .lossless)
        let decoded = try await JP3DVolumeDocument.decode(from: doc)

        // Compare pixel data of each reconstructed slice
        for (i, original) in series.enumerated() {
            let origPx = original.dataSet[.pixelData]!.valueData
            let decodedPx = decoded[i].dataSet[.pixelData]!.valueData
            #expect(origPx == decodedPx, "Slice \(i) pixel data mismatch")
        }
    }

    @Test("encode/decode round-trip keeps MONOCHROME1 (PS3.3 C.7.6.3.1.2) instead of forcing MONOCHROME2")
    func test_roundTrip_monochrome1() async throws {
        let studyUID = UIDGenerator.generateUID().value
        let seriesUID = UIDGenerator.generateUID().value
        let series = try (0..<3).map { i in
            try makeGrayscaleFile(rows: 8, columns: 8, sliceIndex: i, seriesUID: seriesUID,
                                  studyUID: studyUID, photometric: "MONOCHROME1")
        }
        let doc = try await JP3DVolumeDocument.encode(series: series, compressionMode: .lossless)
        let decoded = try await JP3DVolumeDocument.decode(from: doc)
        #expect(decoded.count == 3)
        for slice in decoded {
            #expect(slice.dataSet.string(for: .photometricInterpretation) == "MONOCHROME1")
            #expect(slice.dataSet.uint16(for: .highBit) == 11)
        }
        // Stored values are kept as written (no inversion).
        #expect(decoded[1].dataSet[.pixelData]?.valueData == series[1].dataSet[.pixelData]?.valueData)
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

    @Test("encode/decode round-trip assigns unique SOP Instance UIDs per slice")
    func test_roundTrip_uniqueSOPInstanceUIDs() async throws {
        let series = try makeSeries(slices: 4)
        let doc = try await JP3DVolumeDocument.encode(series: series, compressionMode: .lossless)
        let decoded = try await JP3DVolumeDocument.decode(from: doc)

        let uids = decoded.compactMap { $0.dataSet.string(for: .sopInstanceUID) }
        let uniqueUIDs = Set(uids)
        #expect(uids.count == 4)
        #expect(uniqueUIDs.count == 4) // All unique
    }

    @Test("encode/decode round-trip preserves instance numbers")
    func test_roundTrip_instanceNumbers() async throws {
        let series = try makeSeries(slices: 4)
        let doc = try await JP3DVolumeDocument.encode(series: series, compressionMode: .lossless)
        let decoded = try await JP3DVolumeDocument.decode(from: doc)

        for (i, file) in decoded.enumerated() {
            let num = file.dataSet.string(for: .instanceNumber).flatMap(Int.init)
            #expect(num == i + 1)
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

    // MARK: - Write / Re-Read Round-Trip

    @Test("JP3D document serialises and re-reads correctly")
    func test_writeAndReRead() async throws {
        let series = try makeSeries(slices: 4, rows: 8, columns: 8)
        let doc = try await JP3DVolumeDocument.encode(series: series, compressionMode: .lossless)

        // Serialise to Data and re-parse
        let data = try doc.write()
        #expect(data.count > 132) // At least preamble + DICM

        let reparsed = try DICOMFile.read(from: data)
        #expect(JP3DVolumeDocument.isJP3DVolumeDocument(reparsed))

        // Decode from re-parsed file
        let decoded = try await JP3DVolumeDocument.decode(from: reparsed)
        #expect(decoded.count == 4)
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

        let doc = try await JP3DVolumeDocument.encode(series: series, compressionMode: .lossless)
        let tmpURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("test_jp3d_\(UUID().uuidString).dcm")
        defer { try? FileManager.default.removeItem(at: tmpURL) }
        try (try doc.write()).write(to: tmpURL)

        let volume = try await DICOMFile.openVolume(from: tmpURL)
        #expect(volume.width == columns)
        #expect(volume.height == rows)
        #expect(volume.depth == slices)
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
