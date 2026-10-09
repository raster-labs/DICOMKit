//
// Volume3DContractTests.swift
// dicom-3d
//
// Volume assembly, plane names, derived MPR series, windowing and export geometry
// pinned to DICOM 2026a: PS3.3 Table C.7-10 (Pixel Spacing value 1 = adjacent row
// spacing, value 2 = adjacent column spacing), C.7.6.2.1.1 (Equation C.7.6.2.1-1,
// LPS axes), C.7.4.1.1.1 (one Frame of Reference UID), Tables C.7.6.16-2/-4/-5
// (per-frame geometry), C.7.6.1.1.2 / C.8.3.1.1.1 (Image Type), C.12.4 Table C.12-10,
// PS3.16 CID 7203 / CID 7202, C.11.2.1.2.1 (LINEAR window), C.7.6.3.1.2 (MONOCHROME1).
//

import XCTest
import ArgumentParser
import DICOMCore
import DICOMKit
@testable import dicom_3d

private typealias V3 = dicom_3d.Point3D

final class Volume3DContractTests: XCTestCase {

    // MARK: - Fixtures

    private static func sequenceElement(_ tag: Tag, _ items: [SequenceItem]) -> DataElement {
        var holder = DataSet()
        holder.setSequence(items, for: tag)
        return holder[tag]!
    }

    /// One 16-bit MONOCHROME2 slice whose stored value at (column c, row r) is `value(c, r)`.
    private static func slice(rows: Int = 3, columns: Int = 4,
                              position: [Double], orientation: [Double] = [1, 0, 0, 0, 1, 0],
                              pixelSpacing: [Double] = [0.5, 0.8], instanceNumber: Int = 1,
                              frameOfReference: String = "1.2.3.4.5",
                              modality: String = "CT", slope: Double = 1, intercept: Double = 0,
                              photometric: String = "MONOCHROME2",
                              value: (Int, Int) -> UInt16 = { c, r in UInt16(r * 10 + c) }) -> DICOMFile {
        var ds = DataSet()
        let uid = UIDGenerator.generateUID().value
        ds.setString("1.2.840.10008.5.1.4.1.1.2", for: .sopClassUID, vr: .UI)
        ds.setString(uid, for: .sopInstanceUID, vr: .UI)
        ds.setString("1.2.3", for: .studyInstanceUID, vr: .UI)
        ds.setString("1.2.3.1", for: .seriesInstanceUID, vr: .UI)
        ds.setString(frameOfReference, for: .frameOfReferenceUID, vr: .UI)
        ds.setString(modality, for: .modality, vr: .CS)
        ds.setStrings(["ORIGINAL", "PRIMARY", "AXIAL"], for: .imageType, vr: .CS)
        ds.setInt(instanceNumber, for: .instanceNumber, vr: .IS)
        ds.setStrings(position.map { String($0) }, for: .imagePositionPatient, vr: .DS)
        ds.setStrings(orientation.map { String($0) }, for: .imageOrientationPatient, vr: .DS)
        ds.setStrings(pixelSpacing.map { String($0) }, for: .pixelSpacing, vr: .DS)
        ds.setString("1", for: .sliceThickness, vr: .DS)
        ds.setString(String(slope), for: .rescaleSlope, vr: .DS)
        ds.setString(String(intercept), for: .rescaleIntercept, vr: .DS)
        ds.setUInt16(UInt16(rows), for: .rows)
        ds.setUInt16(UInt16(columns), for: .columns)
        ds.setUInt16(16, for: .bitsAllocated)
        ds.setUInt16(12, for: .bitsStored)
        ds.setUInt16(11, for: .highBit)
        ds.setUInt16(0, for: .pixelRepresentation)
        ds.setUInt16(1, for: .samplesPerPixel)
        ds.setString(photometric, for: .photometricInterpretation, vr: .CS)
        var data = Data()
        for r in 0..<rows { for c in 0..<columns {
            let v = value(c, r); data.append(UInt8(v & 0xFF)); data.append(UInt8(v >> 8))
        } }
        ds[.pixelData] = DataElement.data(tag: .pixelData, vr: .OW, data: data)
        return DICOMFile.create(dataSet: ds, sopClassUID: "1.2.840.10008.5.1.4.1.1.2", sopInstanceUID: uid)
    }

    /// Axial stack: z = 10, 12, 14 given out of order and with reversed Instance Numbers.
    private static func axialStack() -> [DICOMFile] {
        [slice(position: [-10, -20, 14], instanceNumber: 1, value: { c, r in UInt16(200 + r * 10 + c) }),
         slice(position: [-10, -20, 10], instanceNumber: 3, value: { c, r in UInt16(r * 10 + c) }),
         slice(position: [-10, -20, 12], instanceNumber: 2, value: { c, r in UInt16(100 + r * 10 + c) })]
    }

    private func assertClose(_ a: V3, _ b: V3, accuracy: Double = 1e-9,
                             file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(a.x, b.x, accuracy: accuracy, file: file, line: line)
        XCTAssertEqual(a.y, b.y, accuracy: accuracy, file: file, line: line)
        XCTAssertEqual(a.z, b.z, accuracy: accuracy, file: file, line: line)
    }

    // MARK: - Volume assembly (PS3.3 Table C.7-10, C.7.6.2.1.1, C.7.4.1.1.1)

    func testPixelSpacingValueOneIsRowSpacing() throws {
        let volume = try VolumeLoader().loadVolume(files: Self.axialStack())
        // Pixel Spacing "0.5\0.8": 0.5 mm between rows (y), 0.8 mm between columns (x).
        XCTAssertEqual(volume.spacing.x, 0.8)
        XCTAssertEqual(volume.spacing.y, 0.5)
        XCTAssertEqual(volume.spacing.z, 2.0, accuracy: 1e-12)
    }

    func testSlicesSortedAlongNormalNotInstanceNumber() throws {
        let volume = try VolumeLoader().loadVolume(files: Self.axialStack())
        assertClose(volume.origin, V3(x: -10, y: -20, z: 10))
        XCTAssertEqual(volume.voxelAt(x: 1, y: 2, z: 0), 21)
        XCTAssertEqual(volume.voxelAt(x: 1, y: 2, z: 1), 121)
        XCTAssertEqual(volume.voxelAt(x: 1, y: 2, z: 2), 221)
    }

    func testPhysicalCoordinatesFollowEquationC7621() throws {
        // Sagittal acquisition: rows run posterior (+y), columns toward the feet (-z);
        // normal = row x column = (-1, 0, 0). Slices at x = 5, 3, 1.
        let iop: [Double] = [0, 1, 0, 0, 0, -1]
        let files = [5.0, 3.0, 1.0].map { Self.slice(position: [$0, -50, 60], orientation: iop) }
        let volume = try VolumeLoader().loadVolume(files: files)
        XCTAssertEqual(volume.spacing.z, 2.0, accuracy: 1e-12)
        assertClose(volume.origin, V3(x: 5, y: -50, z: 60))
        // P = S + X·Δi·i + Y·Δj·j + N·Δk·k with Δi = 0.8 (value 2), Δj = 0.5 (value 1).
        assertClose(volume.physicalCoordinates(x: 2, y: 1, z: 2),
                    V3(x: 5 - 4, y: -50 + 1.6, z: 60 - 0.5))
    }

    func testMixedFrameOfReferenceRejected() {
        var files = Self.axialStack()
        files[0] = Self.slice(position: [-10, -20, 14], frameOfReference: "1.2.3.4.6")
        XCTAssertThrowsError(try VolumeLoader().loadVolume(files: files)) { error in
            XCTAssertTrue("\(error)".contains("Frame of Reference UID"))
        }
    }

    func testMixedOrientationRejected() {
        var files = Self.axialStack()
        files[0] = Self.slice(position: [-10, -20, 14], orientation: [0, 1, 0, 0, 0, -1])
        XCTAssertThrowsError(try VolumeLoader().loadVolume(files: files))
    }

    func testRescaleAppliedPerSlice() throws {
        let files = [Self.slice(position: [0, 0, 0], slope: 1, intercept: -1024),
                     Self.slice(position: [0, 0, 1], slope: 2, intercept: -1000)]
        let volume = try VolumeLoader().loadVolume(files: files)
        XCTAssertEqual(volume.voxelAt(x: 0, y: 0, z: 0), -1024)
        XCTAssertEqual(volume.voxelAt(x: 1, y: 0, z: 1), 2 * 1 - 1000)
    }

    func testSingleSliceUsesSpacingBetweenSlicesBeforeSliceThickness() throws {
        let file = Self.slice(position: [0, 0, 0])
        var ds = file.dataSet
        ds.setString("3", for: .spacingBetweenSlices, vr: .DS)
        let volume = try VolumeLoader().loadVolume(files: [DICOMFile(fileMetaInformation: file.fileMetaInformation, dataSet: ds)])
        XCTAssertEqual(volume.spacing.z, 3)
    }

    func testEnhancedMultiFrameUsesPlanePositionPerFrame() throws {
        // Two frames; geometry only in the functional groups (Tables C.7.6.16-2/-4/-5).
        var ds = Self.slice(position: [0, 0, 0]).dataSet
        for tag in [Tag.imagePositionPatient, .imageOrientationPatient, .pixelSpacing] { ds.remove(tag: tag) }
        ds.setString("2", for: .numberOfFrames, vr: .IS)
        var frameData = ds[.pixelData]!.valueData
        frameData.append(Data(frameData.map { _ in UInt8(1) }))
        ds[.pixelData] = DataElement.data(tag: .pixelData, vr: .OW, data: frameData)
        let measures = SequenceItem(elements: [DataElement.string(tag: .pixelSpacing, vr: .DS, value: "0.5\\0.8")])
        let orientation = SequenceItem(elements: [DataElement.string(tag: .imageOrientationPatient, vr: .DS, value: "1\\0\\0\\0\\1\\0")])
        let shared = SequenceItem(elements: [Self.sequenceElement(.pixelMeasuresSequence, [measures]),
                                             Self.sequenceElement(.planeOrientationSequence, [orientation])])
        ds.setSequence([shared], for: .sharedFunctionalGroupsSequence)
        let perFrame = ["7", "4"].map { z in
            SequenceItem(elements: [Self.sequenceElement(.planePositionSequence, [
                SequenceItem(elements: [DataElement.string(tag: .imagePositionPatient, vr: .DS, value: "1\\2\\\(z)")])])])
        }
        ds.setSequence(perFrame, for: .perFrameFunctionalGroupsSequence)
        let file = DICOMFile.create(dataSet: ds, sopClassUID: "1.2.840.10008.5.1.4.1.1.2.1")
        let volume = try VolumeLoader().loadVolume(files: [file])
        XCTAssertEqual(volume.dimensions.depth, 2)
        assertClose(volume.origin, V3(x: 1, y: 2, z: 4))
        XCTAssertEqual(volume.spacing.z, 3, accuracy: 1e-12)
        XCTAssertEqual(volume.spacing.x, 0.8)
        // frame 2 (z = 4) is first after sorting: its values are the 0x0101 bytes
        XCTAssertEqual(volume.voxelAt(x: 0, y: 0, z: 0), 257)
    }

    func testClassicMultiFrameWithoutPlanePositionsRejected() {
        var ds = Self.slice(position: [0, 0, 0]).dataSet
        ds.setString("2", for: .numberOfFrames, vr: .IS)
        XCTAssertThrowsError(try VolumeLoader().loadVolume(
            files: [DICOMFile.create(dataSet: ds, sopClassUID: "1.2.840.10008.5.1.4.1.1.2")]))
    }

    func testSortedByPositionForEncodeVolume() {
        let sorted = VolumeLoader.sortedByPosition(Self.axialStack())
        XCTAssertEqual(sorted.map { $0.dataSet.string(for: .instanceNumber) }, ["3", "2", "1"])
    }

    // MARK: - Plane names (PS3.3 C.7.6.2.1.1 LPS)

    func testPlaneLayoutForAxialAcquisition() throws {
        let volume = try VolumeLoader().loadVolume(files: Self.axialStack())
        XCTAssertEqual(ReformatLayout(plane: .axial, volume: volume),
                       ReformatLayout(fixedAxis: 2, uAxis: 0, uReversed: false, vAxis: 1, vReversed: false))
        // Coronal / sagittal: columns run toward the feet (-z), so the stack is read top-down.
        XCTAssertEqual(ReformatLayout(plane: .coronal, volume: volume),
                       ReformatLayout(fixedAxis: 1, uAxis: 0, uReversed: false, vAxis: 2, vReversed: true))
        XCTAssertEqual(ReformatLayout(plane: .sagittal, volume: volume),
                       ReformatLayout(fixedAxis: 0, uAxis: 1, uReversed: false, vAxis: 2, vReversed: true))
    }

    func testPlaneLayoutForSagittalAcquisition() throws {
        let iop: [Double] = [0, 1, 0, 0, 0, -1]
        let files = [5.0, 3.0, 1.0].map { Self.slice(position: [$0, -50, 60], orientation: iop) }
        let volume = try VolumeLoader().loadVolume(files: files)
        // "sagittal" is the acquired plane, cut along the stack.
        XCTAssertEqual(ReformatLayout(plane: .sagittal, volume: volume).fixedAxis, 2)
        // "axial" is perpendicular to z: the column axis of the acquisition.
        XCTAssertEqual(ReformatLayout(plane: .axial, volume: volume).fixedAxis, 1)
        XCTAssertEqual(ReformatLayout(plane: .coronal, volume: volume).fixedAxis, 0)
    }

    func testReformattedGeometryMapsEveryPixelToItsVoxel() throws {
        let volume = try VolumeLoader().loadVolume(files: Self.axialStack())
        for plane in PatientPlane.allCases {
            let layout = ReformatLayout(plane: plane, volume: volume)
            let slices = try MPRGenerator(volume: volume).generateMPR(
                plane: plane == .axial ? .axial : plane == .sagittal ? .sagittal : .coronal)
            XCTAssertEqual(slices.count, volume.axisCount(layout.fixedAxis))
            let k = 1
            let image = slices[k]
            let g = try XCTUnwrap(image.geometry)
            XCTAssertGreaterThanOrEqual(g.rowCosines.dot(plane.rowDirection), 0.99)
            XCTAssertGreaterThanOrEqual(g.columnCosines.dot(plane.columnDirection), 0.99)
            for j in 0..<image.height { for i in 0..<image.width {
                let index = layout.index(i: i, j: j, k: k, volume: volume)
                XCTAssertEqual(image.pixels[j * image.width + i], volume.voxelAt(index))
                // Equation C.7.6.2.1-1: Δi = value 2 (column spacing), Δj = value 1 (row spacing)
                let p = g.imagePosition + g.rowCosines.scaled(g.columnSpacing * Double(i))
                    + g.columnCosines.scaled(g.rowSpacing * Double(j))
                assertClose(p, volume.physicalCoordinates(x: index[0], y: index[1], z: index[2]))
            } }
        }
    }

    func testSlabProjectionIsCentredAndThickMPRAverages() throws {
        let volume = try VolumeLoader().loadVolume(files: Self.axialStack())
        let renderer = ProjectionRenderer(volume: volume)
        // Slab of 2 mm = 1 slice, centred: the middle slice (z = 12).
        let mip = try renderer.maximumIntensityProjection(direction: .axial, slabThickness: 2)
        XCTAssertEqual(mip.pixels[0], 100)
        let full = try renderer.maximumIntensityProjection(direction: .axial)
        XCTAssertEqual(full.pixels[0], 200)
        let minip = try renderer.minimumIntensityProjection(direction: .axial)
        XCTAssertEqual(minip.pixels[0], 0)
        let thick = try MPRGenerator(volume: volume).generateMPR(plane: .axial, sliceThickness: 4)
        XCTAssertEqual(thick.count, 2)
        XCTAssertEqual(thick[0].pixels[0], 50)
        XCTAssertEqual(thick[0].geometry?.sliceThickness, 4)
    }

    // MARK: - Derived series (C.7.6.1.1.2, C.12.4, CID 7203)

    func testDerivedMPRInstances() throws {
        let files = [Self.slice(position: [0, 0, 0], intercept: -1024),
                     Self.slice(position: [0, 0, 2], intercept: -1024)]
        let volume = try VolumeLoader().loadVolume(files: files)
        let slices = try MPRGenerator(volume: volume).generateMPR(plane: .coronal)
        let out = try DerivedSeries.makeInstances(slices: slices, plane: .coronal, volume: volume,
                                                  seriesInstanceUID: "1.2.3.9")
        XCTAssertEqual(out.count, 3)
        let ds = out[1].dataSet
        XCTAssertEqual(ds.strings(for: .imageType), ["DERIVED", "SECONDARY", "AXIAL"])
        XCTAssertEqual(ds.string(for: .sopClassUID), "1.2.840.10008.5.1.4.1.1.2")
        XCTAssertEqual(ds.string(for: .seriesInstanceUID), "1.2.3.9")
        XCTAssertFalse(files.map { $0.dataSet.string(for: .sopInstanceUID) }.contains(ds.string(for: .sopInstanceUID)))
        XCTAssertEqual(ds.string(for: .frameOfReferenceUID), "1.2.3.4.5")
        // PS3.16 2026a CID 7203 row: DCM 113072 "Multiplanar reformatting"
        let code = try XCTUnwrap(ds.sequence(for: .derivationCodeSequence)?.first)
        XCTAssertEqual(code.string(for: .codeValue), "113072")
        XCTAssertEqual(code.string(for: .codingSchemeDesignator), "DCM")
        XCTAssertEqual(code.string(for: .codeMeaning), "Multiplanar reformatting")
        let sources = try XCTUnwrap(ds.sequence(for: .sourceImageSequence))
        XCTAssertEqual(sources.count, 2)
        XCTAssertEqual(sources[0].string(for: .referencedSOPInstanceUID), files[0].dataSet.string(for: .sopInstanceUID))
        // Coronal of an axial stack: row +x, column -z (feet), rows 2 mm apart, columns 0.8 mm.
        XCTAssertEqual(ds.strings(for: .imageOrientationPatient), ["1", "0", "0", "0", "0", "-1"])
        XCTAssertEqual(ds.strings(for: .pixelSpacing), ["2", "0.8"])
        XCTAssertEqual(ds.strings(for: .imagePositionPatient), ["0", "0.5", "2"])
        XCTAssertEqual(ds.uint16(for: .rows), 2)
        XCTAssertEqual(ds.uint16(for: .columns), 4)
        // Stored values go back through the source rescale: stored = HU + 1024.
        let pixels = try XCTUnwrap(out[1].pixelData()?.pixelValues(forFrame: 0))
        XCTAssertEqual(pixels[2], 12)   // column 2 of row 1 (z = 0 after the flip)
    }

    func testDerivedImageTypeValue3ForMR() {
        XCTAssertEqual(DerivedSeries.imageType(source: ["ORIGINAL", "PRIMARY", "M", "SE"], modality: "MR"),
                       ["DERIVED", "SECONDARY", "MPR"])
        XCTAssertEqual(DerivedSeries.imageType(source: ["ORIGINAL", "PRIMARY", "AXIAL"], modality: "CT"),
                       ["DERIVED", "SECONDARY", "AXIAL"])
    }

    // MARK: - Window / VOI (C.11.2.1.2.1, C.7.6.3.1.2)

    func testWindowIsLinearFunction() {
        let image = SliceImage(width: 3, height: 1, pixels: [-161, 40, 240])
        // LINEAR, c = 40, w = 400: x <= c - 0.5 - (w-1)/2 -> 0; x > c - 0.5 + (w-1)/2 -> max
        XCTAssertEqual(image.displayValues(windowCenter: 40, windowWidth: 400), [0, 128, 255])
        XCTAssertEqual(image.displayValues(windowCenter: 40, windowWidth: 400, monochrome1: true), [255, 127, 0])
    }

    func testWindowWidthBelowOneRejected() {
        XCTAssertThrowsError(try MPRCommand.parse(["a.dcm", "-o", "out", "--window-center", "40", "--window-width", "0.5"]))
        XCTAssertThrowsError(try MIPCommand.parse(["a.dcm", "-o", "o.png", "--window-center", "40", "--window-width", "0"]))
        XCTAssertThrowsError(try MinIPCommand.parse(["a.dcm", "-o", "o.png", "--direction", "oblique"]))
    }

    // MARK: - Export geometry (C.7.6.2.1.1 LPS → NIfTI RAS)

    func testNIfTIAffineIsRASAndNotRescaledTwice() throws {
        let volume = try VolumeLoader().loadVolume(files: [Self.slice(position: [-10, -20, 10], intercept: -1024),
                                                           Self.slice(position: [-10, -20, 12], intercept: -1024)])
        XCTAssertEqual(volume.niftiSform[0], [-0.8, 0, 0, 10])
        XCTAssertEqual(volume.niftiSform[1], [0, -0.5, 0, 20])
        XCTAssertEqual(volume.niftiSform[2], [0, 0, 2, 10])
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("d3d-\(UUID().uuidString).nii")
        defer { try? FileManager.default.removeItem(at: url) }
        try volume.exportNIfTI(to: url)
        let data = try Data(contentsOf: url)
        let slope = data.subdata(in: 112..<116).withUnsafeBytes { $0.loadUnaligned(as: Float.self) }
        let inter = data.subdata(in: 116..<120).withUnsafeBytes { $0.loadUnaligned(as: Float.self) }
        XCTAssertEqual(slope, 1)
        XCTAssertEqual(inter, 0)
        XCTAssertEqual(data.subdata(in: 344..<348), Data("n+1\0".utf8))
    }

    func testMetaImageOrientation() throws {
        let axial = try VolumeLoader().loadVolume(files: Self.axialStack())
        XCTAssertEqual(axial.metaImageAnatomicalOrientation, "RAI")
        XCTAssertEqual(axial.metaImageTransformMatrix, [1, 0, 0, 0, 1, 0, 0, 0, 1])
        let iop: [Double] = [0, 1, 0, 0, 0, -1]
        let sagittal = try VolumeLoader().loadVolume(files: [5.0, 3.0].map { Self.slice(position: [$0, 0, 0], orientation: iop) })
        XCTAssertEqual(sagittal.metaImageAnatomicalOrientation, "ASL")
    }

    // MARK: - JP3D document (private SOP Class)

    func testEncodeVolumeHelpNamesEngineSOPClass() {
        XCTAssertTrue(EncodeVolumeCommand.configuration.discussion.contains(JP3DVolumeDocument.sopClassUID))
        XCTAssertFalse(JP3DVolumeDocument.sopClassUID.hasPrefix("1.2.840.10008."))
    }
}

// MARK: - P-3D-OBLIQUE, P-3D-INTERPOLATION, P-3D-VOLUME

extension Volume3DContractTests {

    /// Axial stack, 6 columns x 5 rows x 4 slices, Pixel Spacing 0.5\0.8, slices at z = 10..16:
    /// voxel (c, r, k) at LPS (-10 + 0.8c, -20 + 0.5r, 10 + 2k) holds 100 + 10c + 20r + 30k,
    /// a linear function of position, which trilinear interpolation reproduces exactly.
    private static func linearVolume() throws -> VolumeData {
        let files = (0..<4).map { k in
            slice(rows: 5, columns: 6, position: [-10, -20, 10 + 2 * Double(k)], instanceNumber: k + 1,
                  value: { c, r in UInt16(100 + 10 * c + 20 * r + 30 * k) })
        }
        return try VolumeLoader().loadVolume(files: files)
    }

    /// The known value at an LPS point of `linearVolume`.
    private static func expected(_ p: V3) -> Double {
        let c = (p.x + 10) / 0.8, r = (p.y + 20) / 0.5, k = (p.z - 10) / 2
        return 100 + 10 * c + 20 * r + 30 * k
    }

    /// D207: voxel centres are at integer indices (C.7.6.2.1.1); nearest-neighbour
    /// sampling in the last half voxel of the accepted range [0, n) returns the last
    /// voxel instead of nil, matching trilinear sampling there.
    func testNearestSamplingCoversTheEdgeHalfVoxel() throws {
        let volume = try Self.linearVolume()   // 6 x 5 x 4
        let last = try XCTUnwrap(volume.voxelAt(x: 5, y: 4, z: 3))
        XCTAssertEqual(volume.interpolatedVoxelAt(x: 5.7, y: 4.6, z: 3.9, method: .nearest), last)
        XCTAssertEqual(volume.interpolatedVoxelAt(x: 5.7, y: 4.6, z: 3.9, method: .linear), last)
        XCTAssertEqual(volume.interpolatedVoxelAt(x: 0.4, y: 0.4, z: 0.4, method: .nearest),
                       volume.voxelAt(x: 0, y: 0, z: 0))
        XCTAssertNil(volume.interpolatedVoxelAt(x: 6, y: 0, z: 0, method: .nearest))
        XCTAssertNil(volume.interpolatedVoxelAt(x: -0.1, y: 0, z: 0, method: .nearest))
    }

    func testObliquePlaneDirectionsAreOrthonormalAndInThePlane() throws {
        let plane = try XCTUnwrap(ObliquePlane(normal: V3(x: 0, y: 2, z: 2), point: V3(x: 0, y: 0, z: 0)))
        let s = 1 / 2.0.squareRoot()
        assertClose(plane.normal, V3(x: 0, y: s, z: s))
        assertClose(plane.rowDirection, V3(x: 1, y: 0, z: 0))        // axial row, already in the plane
        assertClose(plane.columnDirection, V3(x: 0, y: s, z: -s))    // axial column projected
        XCTAssertEqual(plane.rowDirection.dot(plane.columnDirection), 0, accuracy: 1e-12)
        XCTAssertEqual(abs(plane.rowDirection.cross(plane.columnDirection).dot(plane.normal)), 1, accuracy: 1e-12)
        XCTAssertNil(ObliquePlane(normal: V3(x: 0, y: 0, z: 0), point: .zero))
        // Near-coronal normal: rows +x, columns toward the feet, as a coronal image
        let coronal = try XCTUnwrap(ObliquePlane(normal: V3(x: 0, y: 1, z: 0.1), point: .zero))
        XCTAssertGreaterThan(coronal.rowDirection.x, 0.99)
        XCTAssertLessThan(coronal.columnDirection.z, -0.99)
    }

    /// Equation C.7.6.2.1-1: pixel (i, j) of the oblique image is at S + X·Δ·i + Y·Δ·j and
    /// holds the volume's value there.
    func testObliqueSamplesFollowEquationC7621() throws {
        let volume = try Self.linearVolume()
        let point = V3(x: -10 + 0.8 * 2, y: -20 + 0.5 * 2, z: 12)       // voxel (2, 2, 1): 190
        let slices = try MPRGenerator(volume: volume, interpolation: .linear)
            .generateMPR(plane: .oblique(normal: V3(x: 0, y: 1, z: 1), point: point))
        XCTAssertEqual(slices.count, 1)
        let image = slices[0]
        let g = try XCTUnwrap(image.geometry)
        XCTAssertEqual(g.rowSpacing, 0.5)
        XCTAssertEqual(g.columnSpacing, 0.5)
        // The point lies on a pixel centre
        let rel = point - g.imagePosition
        let i0 = rel.dot(g.rowCosines) / 0.5, j0 = rel.dot(g.columnCosines) / 0.5
        XCTAssertEqual(i0, i0.rounded(), accuracy: 1e-9)
        XCTAssertEqual(j0, j0.rounded(), accuracy: 1e-9)
        let (pi, pj) = (Int(i0.rounded()), Int(j0.rounded()))
        XCTAssertEqual(image.pixels[pj * image.width + pi], 190, accuracy: 1e-9)
        // Neighbours: +1 column = +0.5 mm along x = +6.25; +1 row = (0, +0.354, -0.354) mm = +8.839
        XCTAssertEqual(image.pixels[pj * image.width + pi + 1], 196.25, accuracy: 1e-9)
        XCTAssertEqual(image.pixels[(pj + 1) * image.width + pi], 190 + 20 * 0.5 / 2.0.squareRoot() / 0.5
                       - 30 * 0.5 / 2.0.squareRoot() / 2, accuracy: 1e-9)
        // Every pixel inside the volume matches the known function at its Equation C.7.6.2.1-1 position
        var checked = 0
        for j in 0..<image.height {
            for i in 0..<image.width {
                let p = g.imagePosition + g.rowCosines.scaled(0.5 * Double(i)) + g.columnCosines.scaled(0.5 * Double(j))
                let c = (p.x + 10) / 0.8, r = (p.y + 20) / 0.5, k = (p.z - 10) / 2
                guard c >= 0, c <= 5, r >= 0, r <= 4, k >= 0, k <= 3 else { continue }
                XCTAssertEqual(image.pixels[j * image.width + i], Self.expected(p), accuracy: 1e-9)
                checked += 1
            }
        }
        XCTAssertGreaterThan(checked, 20)
        // Nearest neighbour reads the voxel itself at a voxel centre
        let nearest = try MPRGenerator(volume: volume, interpolation: .nearest)
            .generateMPR(plane: .oblique(normal: V3(x: 0, y: 1, z: 1), point: point))[0]
        XCTAssertEqual(nearest.pixels[pj * nearest.width + pi], 190)
    }

    func testObliqueDerivedImageCarriesThePlaneGeometry() throws {
        let volume = try Self.linearVolume()
        let point = V3(x: -10 + 0.8 * 2, y: -20 + 0.5 * 2, z: 12)
        let slices = try MPRGenerator(volume: volume)
            .generateMPR(plane: .oblique(normal: V3(x: 0, y: 1, z: 1), point: point))
        let out = try DerivedSeries.makeInstances(slices: slices, planeName: "oblique", volume: volume,
                                                  seriesInstanceUID: "1.2.3.10")
        let ds = try XCTUnwrap(out.first?.dataSet)
        XCTAssertEqual(ds.strings(for: .imageOrientationPatient),
                       ["1", "0", "0", "0", "0.7071067812", "-0.7071067812"])
        let g = try XCTUnwrap(slices[0].geometry)
        XCTAssertEqual(ds.strings(for: .imagePositionPatient),
                       [g.imagePosition.x, g.imagePosition.y, g.imagePosition.z].map(DerivedSeries.formatted))
        XCTAssertEqual(ds.strings(for: .pixelSpacing), ["0.5", "0.5"])
        XCTAssertEqual(ds.string(for: .seriesDescription), "MPR oblique")
        XCTAssertEqual(ds.string(for: .derivationDescription), "Multiplanar reformatting, oblique plane, by dicom-3d")
        XCTAssertEqual(ds.strings(for: .imageType), ["DERIVED", "SECONDARY", "AXIAL"])
        let pixels = try XCTUnwrap(out[0].pixelData()?.pixelValues(forFrame: 0))
        let rel = point - g.imagePosition
        let index = Int((rel.dot(g.columnCosines) / 0.5).rounded()) * slices[0].width + Int((rel.dot(g.rowCosines) / 0.5).rounded())
        XCTAssertEqual(pixels[index], 190)
    }

    func testObliqueOptionsAreValidated() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("dicom3d-oblique-\(UUID().uuidString).dcm")
        try Data([0]).write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        let base = [file.path, "-o", "out"]
        XCTAssertThrowsError(try MPRCommand.parse(base + ["--planes", "oblique"]))
        XCTAssertThrowsError(try MPRCommand.parse(base + ["--planes", "oblique", "--oblique-normal", "0,0,0"]))
        XCTAssertThrowsError(try MPRCommand.parse(base + ["--planes", "oblique", "--oblique-normal", "1,2"]))
        XCTAssertThrowsError(try MPRCommand.parse(base + ["--planes", "axial", "--oblique-normal", "0,0,1"]))
        XCTAssertThrowsError(try MPRCommand.parse(base + ["--planes", "oblique", "--oblique-normal", "0,0,1",
                                                          "--oblique-point", "x"]))
        XCTAssertNoThrow(try MPRCommand.parse(base + ["--planes", "oblique", "--oblique-normal", "0,1,1",
                                                      "--oblique-point", "0,-20,35"]))
    }

    func testCubicInterpolationIsDeprecatedAndUsesLinear() {
        XCTAssertEqual(InterpolationMethod.cubic.effective, .linear)
        XCTAssertEqual(InterpolationMethod.nearest.effective, .nearest)
        XCTAssertNotNil(InterpolationMethod.cubic.deprecationNote)
        XCTAssertNil(InterpolationMethod.linear.deprecationNote)
    }

    func testVolumeSubcommandIsHiddenAndNotImplemented() throws {
        XCTAssertFalse(VolumeCommand.configuration.shouldDisplay)
        var command = try VolumeCommand.parse(["a.dcm", "--camera-angle", "30,10"])
        XCTAssertThrowsError(try command.run()) { error in
            XCTAssertEqual(VolumeCommand.exitCode(for: error).rawValue, 1)
        }
        XCTAssertTrue(VolumeCommand.notImplementedMessage.contains("not implemented"))
    }
}
