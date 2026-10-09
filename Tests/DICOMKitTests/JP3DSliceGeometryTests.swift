import Foundation
import Testing
@testable import DICOMKit
import DICOMCore
import J2KCore

/// D204 / D205 (2026-10-01): JP3DVolumeDocument geometry per PS3.3 2026a C.7.6.2.1.1 —
/// Image Position (Patient) is the centre of the first voxel and Image Orientation (Patient)
/// gives the row and column direction cosines, so the slices of a volume step along the
/// normal (row cosine × column cosine), not along z. Encode records the origin and spacing
/// of the volume in the order JP3DVolumeBridge stacks it (sorted along that normal); decode
/// writes Image Position / Image Orientation (Patient), Pixel Spacing (Table C.7-10), one
/// Frame of Reference UID (C.7.4.1.1.1), the source Rescale and SOP Class.
@Suite("JP3D slice geometry (PS3.3 C.7.6.2.1.1)")
struct JP3DSliceGeometryTests {

    /// Sagittal: rows along +y (anterior → posterior), columns along -z (head → feet).
    /// Normal = (0,1,0) × (0,0,-1) = (-1,0,0).
    private let sagittal: [Double] = [0, 1, 0, 0, 0, -1]

    private func slice(index: Int, x: Double, frameOfReference: String) throws -> DICOMFile {
        let rows = 8, columns = 8
        var pixels = Data()
        for p in 0..<(rows * columns) {
            var v = UInt16((index * 100 + p) & 0x0FFF).littleEndian
            pixels.append(Data(bytes: &v, count: 2))
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
        ds.setString("MR", for: .modality, vr: .CS)
        ds.setString("1.2.840.10008.5.1.4.1.1.4", for: .sopClassUID, vr: .UI)
        ds.setString(UIDGenerator.generateUID().value, for: .sopInstanceUID, vr: .UI)
        ds.setString("1.2.3", for: .studyInstanceUID, vr: .UI)
        ds.setString("1.2.3.4", for: .seriesInstanceUID, vr: .UI)
        ds.setString(frameOfReference, for: .frameOfReferenceUID, vr: .UI)
        ds.setInt(index + 1, for: .instanceNumber, vr: .IS)
        ds.setString("\(x)\\-100\\50", for: .imagePositionPatient, vr: .DS)
        ds.setString(sagittal.map { String($0) }.joined(separator: "\\"), for: .imageOrientationPatient, vr: .DS)
        ds.setString("0.5\\0.75", for: .pixelSpacing, vr: .DS)
        ds.setString("2", for: .rescaleSlope, vr: .DS)
        ds.setString("-10", for: .rescaleIntercept, vr: .DS)
        ds[.pixelData] = DataElement.data(tag: .pixelData, vr: .OW, data: pixels)
        return try DICOMFile.create(dataSet: ds, sopClassUID: "1.2.840.10008.5.1.4.1.1.4",
                                    sopInstanceUID: ds.string(for: .sopInstanceUID)!,
                                    transferSyntaxUID: TransferSyntax.explicitVRLittleEndian.uid)
    }

    private func positions(_ file: DICOMFile) -> [Double] {
        (file.dataSet.string(for: .imagePositionPatient) ?? "").split(separator: "\\").compactMap { Double($0) }
    }

    @Test("Equation C.7.6.2.1-1: slices step along row × column cosine")
    func slicePositionAlongNormal() {
        // Axial: normal (0,0,1)
        #expect(JP3DVolumeDocument.slicePosition(origin: [1, 2, 3], orientation: [1, 0, 0, 0, 1, 0], spacing: 2.5, index: 2) == [1, 2, 8])
        // Sagittal: normal (-1,0,0) — x changes, z does not
        #expect(JP3DVolumeDocument.slicePosition(origin: [10, -100, 50], orientation: sagittal, spacing: 2, index: 3) == [4, -100, 50])
        // Coronal: rows +x, columns -z; normal (1,0,0) × (0,0,-1) = (0,1,0)
        #expect(JP3DVolumeDocument.slicePosition(origin: [0, 0, 0], orientation: [1, 0, 0, 0, 0, -1], spacing: 1.5, index: 2) == [0, 3, 0])
    }

    @Test("Unsorted sagittal series: decoded slices carry the sorted geometry and pixels")
    func unsortedSagittalRoundTrip() async throws {
        let frameOfReference = "1.2.826.0.1.3680043.10.511.99.1"
        // Projections on the normal (-1,0,0) are -x: x = 10, 8, 6, 4 is ascending order.
        // The input is shuffled; slice index i carries x = 10 - 2i.
        let xs: [Double] = [6, 10, 4, 8]
        let series = try xs.map { x in try slice(index: Int((10 - x) / 2), x: x, frameOfReference: frameOfReference) }

        let document = try await JP3DVolumeDocument.encode(series: series, compressionMode: .lossless)
        let slices = try await JP3DVolumeDocument.decode(from: document)
        #expect(slices.count == 4)

        for (i, file) in slices.enumerated() {
            let ds = file.dataSet
            // Image Position (Patient): x = 10 - 2i, y and z unchanged
            #expect(positions(file) == [10 - 2 * Double(i), -100, 50])
            // Image Orientation (Patient), Pixel Spacing, Frame of Reference UID
            #expect((ds.string(for: .imageOrientationPatient) ?? "").split(separator: "\\").compactMap { Double($0) } == sagittal)
            #expect(ds.string(for: .pixelSpacing) == "0.5\\0.75")
            #expect(ds.string(for: .frameOfReferenceUID) == frameOfReference)
            // Rescale and SOP Class from the source (MR Image Storage, not CT)
            #expect(ds.string(for: .rescaleSlope) == "2")
            #expect(ds.string(for: .rescaleIntercept) == "-10")
            #expect(ds.string(for: .sopClassUID) == "1.2.840.10008.5.1.4.1.1.4")
            // Pixels of the i-th slice in sorted order (index i wrote values i*100 + p)
            let first = ds[.pixelData]?.valueData.prefix(2).withUnsafeBytes { $0.load(as: UInt16.self).littleEndian }
            #expect(first == UInt16(i * 100))
        }
    }

    @Test("Legacy sidecar SOP Class fallback follows Modality")
    func fallbackSOPClass() {
        #expect(JP3DVolumeDocument.fallbackSOPClassUID(modality: "CT") == "1.2.840.10008.5.1.4.1.1.2")
        #expect(JP3DVolumeDocument.fallbackSOPClassUID(modality: "MR") == "1.2.840.10008.5.1.4.1.1.4")
        #expect(JP3DVolumeDocument.fallbackSOPClassUID(modality: "PT") == "1.2.840.10008.5.1.4.1.1.128")
        #expect(JP3DVolumeDocument.fallbackSOPClassUID(modality: "US") == "1.2.840.10008.5.1.4.1.1.7")
    }

    // MARK: - D224: JP3DVolumeBridge.makeDICOMSeries

    @Test("makeVolume keeps the first slice's position; makeDICOMSeries steps along the template normal")
    func bridgeRoundTripKeepsSagittalGeometry() throws {
        let frameOfReference = "1.2.826.0.1.3680043.10.511.99.2"
        let xs: [Double] = [6, 10, 4, 8]
        let series = try xs.map { x in try slice(index: Int((10 - x) / 2), x: x, frameOfReference: frameOfReference) }
        let volume = try JP3DVolumeBridge.makeVolume(from: series)
        // Sorted along the normal (-1,0,0): x = 10 first
        #expect([volume.originX, volume.originY, volume.originZ] == [10, -100, 50])
        #expect(volume.spacingZ == 2)

        let slices = try JP3DVolumeBridge.makeDICOMSeries(from: volume, template: series[0])
        #expect(slices.count == 4)
        for (i, file) in slices.enumerated() {
            #expect(positions(file) == [10 - 2 * Double(i), -100, 50])
            #expect(file.dataSet.string(for: .imageOrientationPatient) == "0\\1\\0\\0\\0\\-1")
            #expect(file.dataSet.string(for: .sliceLocation) == JP3DVolumeDocument.decimalString(-10 + 2 * Double(i)))
            #expect(file.dataSet.string(for: .pixelSpacing) == "0.5\\0.75")
            #expect(file.dataSet.string(for: .frameOfReferenceUID) == frameOfReference)
        }
    }

    @Test("A template without Image Orientation (Patient) gets the axial orientation its z positions assume")
    func bridgeWritesOrientationWithPosition() throws {
        var template = try slice(index: 0, x: 0, frameOfReference: "1.2.3.9").dataSet
        template[.imageOrientationPatient] = nil
        let volume = J2KVolume(
            width: 8, height: 8, depth: 2,
            components: [J2KVolumeComponent(index: 0, bitDepth: 12, signed: false, width: 8, height: 8, depth: 2,
                                            data: Data(count: 8 * 8 * 2 * 2))],
            spacingX: 1, spacingY: 1, spacingZ: 3, originX: 1, originY: 2, originZ: 5)
        let file = DICOMFile(fileMetaInformation: DataSet(), dataSet: template)
        let slices = try JP3DVolumeBridge.makeDICOMSeries(from: volume, template: file)
        #expect(positions(slices[1]) == [1, 2, 8])
        #expect(slices[1].dataSet.string(for: .imageOrientationPatient) == "1\\0\\0\\0\\1\\0")
        #expect(slices[1].dataSet.string(for: .sliceLocation) == "8")
    }
}
