import Foundation
import Testing
@testable import DICOMKit
import DICOMCore

/// Pins `DICOMFile.openVolume` to the Image Plane Module (PS3.3 Table C.7-10,
/// C.7.6.2.1.1) and Image Pixel Module (Table C.7-11c) semantics: slice spacing
/// comes from Image Position (Patient) along the slice normal (or Spacing Between
/// Slices), never from the nominal Slice Thickness when something better exists,
/// and the source Photometric Interpretation / High Bit / Pixel Representation
/// are honoured instead of assumed.
@Suite("Volume spacing and pixel module")
struct VolumeSpacingTests {

    private static let ctSOPClass = "1.2.840.10008.5.1.4.1.1.2"

    private func ds(_ value: Double) -> String { String(format: "%.6f", value) }

    private func makeSlice(
        index: Int,
        position: (Double, Double, Double),
        orientation: [Double]?,
        sliceThickness: String,
        spacingBetweenSlices: String? = nil,
        photometric: String = "MONOCHROME2",
        bitsStored: UInt16 = 12,
        firstPixel: UInt16 = 100
    ) throws -> DICOMFile {
        var ds = DataSet()
        ds.setUInt16(2, for: .rows)
        ds.setUInt16(2, for: .columns)
        ds.setUInt16(16, for: .bitsAllocated)
        ds.setUInt16(bitsStored, for: .bitsStored)
        ds.setUInt16(bitsStored - 1, for: .highBit)
        ds.setUInt16(0, for: .pixelRepresentation)
        ds.setUInt16(1, for: .samplesPerPixel)
        ds.setString(photometric, for: .photometricInterpretation, vr: .CS)
        ds.setString("CT", for: .modality, vr: .CS)
        ds.setString("1.2.3.4", for: .studyInstanceUID, vr: .UI)
        ds.setString("1.2.3.4.5", for: .seriesInstanceUID, vr: .UI)
        ds.setString("1.2.3.4.5.\(index + 1)", for: .sopInstanceUID, vr: .UI)
        ds.setString(Self.ctSOPClass, for: .sopClassUID, vr: .UI)
        ds.setInt(index + 1, for: .instanceNumber, vr: .IS)
        ds.setString("\(self.ds(position.0))\\\(self.ds(position.1))\\\(self.ds(position.2))",
                     for: .imagePositionPatient, vr: .DS)
        if let orientation {
            ds.setString(orientation.map(self.ds).joined(separator: "\\"), for: .imageOrientationPatient, vr: .DS)
        }
        ds.setString("0.5\\0.75", for: .pixelSpacing, vr: .DS) // row spacing 0.5, column spacing 0.75
        ds.setString(sliceThickness, for: .sliceThickness, vr: .DS)
        if let spacingBetweenSlices {
            ds.setString(spacingBetweenSlices, for: .spacingBetweenSlices, vr: .DS)
        }
        var pixels = Data()
        for v in [firstPixel, 200, 300, 400] {
            var le = v.littleEndian
            pixels.append(Data(bytes: &le, count: 2))
        }
        ds[.pixelData] = DataElement.data(tag: .pixelData, vr: .OW, data: pixels)
        return try DICOMFile.create(
            dataSet: ds, sopClassUID: Self.ctSOPClass,
            sopInstanceUID: "1.2.3.4.5.\(index + 1)",
            transferSyntaxUID: TransferSyntax.explicitVRLittleEndian.uid)
    }

    private func writeSeries(_ files: [DICOMFile]) throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("volume_spacing_\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        // Reverse file-name order so the result depends on the position sort, not on names.
        for (i, file) in files.enumerated() {
            try file.write().write(to: dir.appendingPathComponent("slice_\(files.count - i).dcm"))
        }
        return dir
    }

    // MARK: - Slice spacing

    @Test("slice spacing is the Image Position (Patient) delta along the normal, not Slice Thickness")
    func sliceSpacing_fromPositionsAlongNormal() async throws {
        // Row cosines (1,0,0), column cosines (0, cos45°, sin45°) → normal (0, −sin45°, cos45°).
        let c = 0.5.squareRoot()
        let orientation = [1.0, 0.0, 0.0, 0.0, c, c]
        let spacing = 2.5
        let files = try (0..<3).map { k in
            try makeSlice(index: k,
                          position: (0, -c * spacing * Double(k), c * spacing * Double(k)),
                          orientation: orientation,
                          sliceThickness: "5.0")
        }
        let dir = try writeSeries(files)
        defer { try? FileManager.default.removeItem(at: dir) }

        let volume = try await DICOMFile.openVolume(from: dir)
        #expect(volume.depth == 3)
        // The z delta alone is 1.7678 and Slice Thickness says 5.0; the standard's
        // centre-to-centre distance along the normal is 2.5.
        #expect(abs(volume.spacingZ - spacing) < 1e-6)
        // Pixel Spacing is "adjacent row spacing \ adjacent column spacing": Y then X.
        #expect(abs(volume.spacingY - 0.5) < 1e-9)
        #expect(abs(volume.spacingX - 0.75) < 1e-9)
        // First slice is the one at the origin regardless of file-name order.
        #expect(abs(volume.originX) < 1e-9 && abs(volume.originY) < 1e-9 && abs(volume.originZ) < 1e-9)
    }

    @Test("without an orientation the Euclidean distance between positions is used")
    func sliceSpacing_euclideanWithoutOrientation() async throws {
        let files = try (0..<2).map { k in
            try makeSlice(index: k, position: (0, 0, 3.0 * Double(k)), orientation: nil, sliceThickness: "1.0")
        }
        let dir = try writeSeries(files)
        defer { try? FileManager.default.removeItem(at: dir) }
        let volume = try await DICOMFile.openVolume(from: dir)
        #expect(abs(volume.spacingZ - 3.0) < 1e-9)
    }

    @Test("a single slice uses Spacing Between Slices before the nominal Slice Thickness")
    func sliceSpacing_singleSlice_prefersSpacingBetweenSlices() async throws {
        let dir = try writeSeries([
            try makeSlice(index: 0, position: (0, 0, 0), orientation: nil,
                          sliceThickness: "5.0", spacingBetweenSlices: "3.0"),
        ])
        defer { try? FileManager.default.removeItem(at: dir) }
        let volume = try await DICOMFile.openVolume(from: dir)
        #expect(abs(volume.spacingZ - 3.0) < 1e-9)
    }

    @Test("a single slice falls back to Slice Thickness only when nothing else exists")
    func sliceSpacing_singleSlice_fallsBackToThickness() async throws {
        let dir = try writeSeries([
            try makeSlice(index: 0, position: (0, 0, 0), orientation: nil, sliceThickness: "5.0"),
        ])
        defer { try? FileManager.default.removeItem(at: dir) }
        let volume = try await DICOMFile.openVolume(from: dir)
        #expect(abs(volume.spacingZ - 5.0) < 1e-9)
    }

    @Test("a multi-frame object uses Spacing Between Slices (0018,0088) over Slice Thickness")
    func sliceSpacing_multiframe_usesSpacingBetweenSlices() async throws {
        var ds = DataSet()
        ds.setUInt16(2, for: .rows)
        ds.setUInt16(2, for: .columns)
        ds.setUInt16(16, for: .bitsAllocated)
        ds.setUInt16(12, for: .bitsStored)
        ds.setUInt16(11, for: .highBit)
        ds.setUInt16(0, for: .pixelRepresentation)
        ds.setUInt16(1, for: .samplesPerPixel)
        ds.setString("MONOCHROME2", for: .photometricInterpretation, vr: .CS)
        ds.setString("2", for: .numberOfFrames, vr: .IS)
        ds.setString("1.2.3.4.5.9", for: .sopInstanceUID, vr: .UI)
        ds.setString(Self.ctSOPClass, for: .sopClassUID, vr: .UI)
        ds.setString("5.0", for: .sliceThickness, vr: .DS)
        ds.setString("1.25", for: .spacingBetweenSlices, vr: .DS)
        ds[.pixelData] = DataElement.data(tag: .pixelData, vr: .OW, data: Data(repeating: 0, count: 16))
        let file = try DICOMFile.create(dataSet: ds, sopClassUID: Self.ctSOPClass,
                                        sopInstanceUID: "1.2.3.4.5.9",
                                        transferSyntaxUID: TransferSyntax.explicitVRLittleEndian.uid)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("mf_\(UUID().uuidString).dcm")
        defer { try? FileManager.default.removeItem(at: url) }
        try file.write().write(to: url)
        let volume = try await DICOMFile.openVolume(from: url)
        #expect(volume.depth == 2)
        #expect(abs(volume.spacingZ - 1.25) < 1e-9)
    }

    // MARK: - Image Pixel Module

    @Test("MONOCHROME1 stored values are preserved, not inverted (inversion is a post-VOI display step)")
    func monochrome1_storedValuesPreserved() async throws {
        let dir = try writeSeries([
            try makeSlice(index: 0, position: (0, 0, 0), orientation: nil, sliceThickness: "1.0",
                          photometric: "MONOCHROME1", firstPixel: 123),
        ])
        defer { try? FileManager.default.removeItem(at: dir) }
        let volume = try await DICOMFile.openVolume(from: dir)
        #expect(volume.voxel(x: 0, y: 0, z: 0) == 123)
        #expect(volume.bitsStored == 12)
        #expect(volume.isSigned == false)
    }

    @Test("the decode descriptor carries the source Photometric Interpretation, High Bit and Pixel Representation")
    func sourceDescriptor_readsImagePixelModule() throws {
        var ds = DataSet()
        ds.setUInt16(16, for: .bitsAllocated)
        ds.setUInt16(12, for: .bitsStored)
        ds.setUInt16(11, for: .highBit)
        ds.setUInt16(1, for: .pixelRepresentation)
        ds.setUInt16(1, for: .samplesPerPixel)
        ds.setString("MONOCHROME1", for: .photometricInterpretation, vr: .CS)
        let d = DICOMFile.sourceDescriptor(from: ds, rows: 4, columns: 5, numberOfFrames: 1)
        #expect(d.photometricInterpretation == .monochrome1)
        #expect(d.highBit == 11)
        #expect(d.isSigned == true)
        #expect(d.bitsStored == 12)

        // High Bit absent → Bits Stored − 1 (PS3.5 8.1.1: "High Bit (0028,0102)
        // shall be one less than Bits Stored (0028,0101)").
        var noHighBit = DataSet()
        noHighBit.setUInt16(16, for: .bitsAllocated)
        noHighBit.setUInt16(10, for: .bitsStored)
        let d2 = DICOMFile.sourceDescriptor(from: noHighBit, rows: 1, columns: 1, numberOfFrames: 1)
        #expect(d2.highBit == 9)
        #expect(d2.photometricInterpretation == .monochrome2)
    }

    // MARK: - Photometric Interpretation and High Bit on the volume (D33)

    @Test("a MONOCHROME1 series yields a volume flagged MONOCHROME1 with the source High Bit")
    func monochrome1_flagAndHighBitCarried() async throws {
        let files = try (0..<2).map { k in
            try makeSlice(index: k, position: (0, 0, Double(k)), orientation: nil, sliceThickness: "1.0",
                          photometric: "MONOCHROME1", bitsStored: 10, firstPixel: 7)
        }
        let dir = try writeSeries(files)
        defer { try? FileManager.default.removeItem(at: dir) }
        let volume = try await DICOMFile.openVolume(from: dir)
        #expect(volume.photometricInterpretation == .monochrome1)
        #expect(volume.isMonochrome1)
        #expect(volume.bitsStored == 10)
        #expect(volume.highBit == 9)
        // Stored values are not inverted (C.7.6.3.1.2 inverts after VOI, at display).
        #expect(volume.voxel(x: 0, y: 0, z: 0) == 7)
    }

    @Test("a MONOCHROME2 series is flagged MONOCHROME2")
    func monochrome2_flagCarried() async throws {
        let dir = try writeSeries([
            try makeSlice(index: 0, position: (0, 0, 0), orientation: nil, sliceThickness: "1.0"),
        ])
        defer { try? FileManager.default.removeItem(at: dir) }
        let volume = try await DICOMFile.openVolume(from: dir)
        #expect(volume.photometricInterpretation == .monochrome2)
        #expect(!volume.isMonochrome1)
        #expect(volume.highBit == 11)
    }

    @Test("slices that disagree on Photometric Interpretation are not merged into one volume")
    func mixedPhotometric_throws() async throws {
        let dir = try writeSeries([
            try makeSlice(index: 0, position: (0, 0, 0), orientation: nil, sliceThickness: "1.0",
                          photometric: "MONOCHROME2"),
            try makeSlice(index: 1, position: (0, 0, 1), orientation: nil, sliceThickness: "1.0",
                          photometric: "MONOCHROME1"),
        ])
        defer { try? FileManager.default.removeItem(at: dir) }
        await #expect(throws: DICOMError.self) { _ = try await DICOMFile.openVolume(from: dir) }
    }

    @Test("slices that disagree on Bits Stored / High Bit are not merged into one volume")
    func mixedHighBit_throws() async throws {
        let dir = try writeSeries([
            try makeSlice(index: 0, position: (0, 0, 0), orientation: nil, sliceThickness: "1.0", bitsStored: 12),
            try makeSlice(index: 1, position: (0, 0, 1), orientation: nil, sliceThickness: "1.0", bitsStored: 16),
        ])
        defer { try? FileManager.default.removeItem(at: dir) }
        await #expect(throws: DICOMError.self) { _ = try await DICOMFile.openVolume(from: dir) }
    }

    @Test("a multi-frame MONOCHROME1 object yields a MONOCHROME1 volume")
    func multiframe_monochrome1Carried() async throws {
        var ds = DataSet()
        ds.setUInt16(2, for: .rows)
        ds.setUInt16(2, for: .columns)
        ds.setUInt16(16, for: .bitsAllocated)
        ds.setUInt16(14, for: .bitsStored)
        ds.setUInt16(13, for: .highBit)
        ds.setUInt16(0, for: .pixelRepresentation)
        ds.setUInt16(1, for: .samplesPerPixel)
        ds.setString("MONOCHROME1", for: .photometricInterpretation, vr: .CS)
        ds.setString("2", for: .numberOfFrames, vr: .IS)
        ds.setString("1.2.3.4.5.10", for: .sopInstanceUID, vr: .UI)
        ds.setString(Self.ctSOPClass, for: .sopClassUID, vr: .UI)
        ds[.pixelData] = DataElement.data(tag: .pixelData, vr: .OW, data: Data(repeating: 0, count: 16))
        let file = try DICOMFile.create(dataSet: ds, sopClassUID: Self.ctSOPClass,
                                        sopInstanceUID: "1.2.3.4.5.10",
                                        transferSyntaxUID: TransferSyntax.explicitVRLittleEndian.uid)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("mf1_\(UUID().uuidString).dcm")
        defer { try? FileManager.default.removeItem(at: url) }
        try file.write().write(to: url)
        let volume = try await DICOMFile.openVolume(from: url)
        #expect(volume.photometricInterpretation == .monochrome1)
        #expect(volume.highBit == 13)
        #expect(volume.bitsStored == 14)
    }

    @Test("DICOMVolume defaults: High Bit = Bits Stored - 1 (Table C.7-11c), MONOCHROME2")
    func volumeInitDefaults() {
        let v = DICOMVolume(width: 1, height: 1, depth: 1, bitsAllocated: 16, bitsStored: 12,
                            pixelData: Data(count: 2))
        #expect(v.highBit == 11)
        #expect(v.photometricInterpretation == .monochrome2)
        #expect(!v.isMonochrome1)
    }

    @Test("voxel() reads the Bits Stored bits ending at High Bit and sign-extends from High Bit")
    func voxel_masksAndSignExtendsFromHighBit() {
        func volume(_ raw: [UInt16], bitsStored: Int, signed: Bool) -> DICOMVolume {
            var data = Data()
            for v in raw { var le = v.littleEndian; data.append(Data(bytes: &le, count: 2)) }
            return DICOMVolume(width: raw.count, height: 1, depth: 1, bitsAllocated: 16,
                               bitsStored: bitsStored, isSigned: signed, pixelData: data)
        }
        // 12-bit two's complement: 0x800 is -2048 (bit 11 is the sign bit), whether
        // or not the writer sign-extended into bits 12-15.
        let signed12 = volume([0x0800, 0xF800, 0xFFFB, 0x07FF], bitsStored: 12, signed: true)
        #expect(signed12.voxel(x: 0, y: 0, z: 0) == -2048)
        #expect(signed12.voxel(x: 1, y: 0, z: 0) == -2048)
        #expect(signed12.voxel(x: 2, y: 0, z: 0) == -5)
        #expect(signed12.voxel(x: 3, y: 0, z: 0) == 2047)
        // Unsigned: bits above High Bit are not part of the sample.
        let unsigned12 = volume([0xF123], bitsStored: 12, signed: false)
        #expect(unsigned12.voxel(x: 0, y: 0, z: 0) == 0x123)
        // Full 16-bit signed.
        let signed16 = volume([0x8000], bitsStored: 16, signed: true)
        #expect(signed16.voxel(x: 0, y: 0, z: 0) == -32768)
        // 8-bit signed.
        let v8 = DICOMVolume(width: 1, height: 1, depth: 1, bitsAllocated: 8, bitsStored: 8,
                             isSigned: true, pixelData: Data([0xFF]))
        #expect(v8.voxel(x: 0, y: 0, z: 0) == -1)
    }
}
