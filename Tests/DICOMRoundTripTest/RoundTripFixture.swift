// RoundTripFixture.swift
// Shared helpers for the oracle-based round-trip test suite.
//
// See ROUND_TRIP_TESTS_PLAN.md (design/oracles). The former ROUND_TRIP_TEST_DATA.md
// tracker was removed 2026-07-17: it pasted dump excerpts and hashed PatientIDs from
// the real Tier 2 corpus. Run the suite for live status; keep corpus output out of docs.
//
// Two fixture tiers:
//   Tier 1 — synthetic builders below (self-contained, pixel-exact oracles, CI-safe)
//   Tier 2 — real anonymized corpus at Tests/DICOMRoundTripTest/Corpus/, resolved
//            at runtime via #filePath with skip-if-absent guards.

import XCTest
import Foundation
@testable import DICOMKit
@testable import DICOMCore
@testable import DICOMDictionary

// MARK: - Synthetic DICOM builders

/// The Type 1 and Type 2 attributes a CT Image (PS3.3 2026a Table A.3-1) must carry
/// beyond identity and Image Pixel: Patient (Table C.7-1), General Study (C.7-3),
/// General Series (C.7-5a, Patient Position 2C), Frame of Reference (C.7-6), General
/// Equipment (C.7-8), General Image (C.7-9), Image Plane (C.7-10) and CT Image (C.8-3).
/// The validator reports every missing one as an error (PS3.5 7.4.1, 7.4.3).
func addCTImageModules(_ ds: inout DataSet) {
    ds.setString("", for: .patientBirthDate, vr: .DA)
    ds.setString("", for: .patientSex, vr: .CS)
    ds.setString("", for: .studyDate, vr: .DA)
    ds.setString("", for: .studyTime, vr: .TM)
    ds.setString("", for: .referringPhysicianName, vr: .PN)
    ds.setString("", for: .studyID, vr: .SH)
    ds.setString("", for: .accessionNumber, vr: .SH)
    ds.setString("", for: .seriesNumber, vr: .IS)
    ds.setString("HFS", for: .patientPosition, vr: .CS)
    ds.setString("1.2.3.4.5.300", for: .frameOfReferenceUID, vr: .UI)
    ds.setString("", for: .positionReferenceIndicator, vr: .LO)
    ds.setString("", for: .manufacturer, vr: .LO)
    ds.setString("", for: .instanceNumber, vr: .IS)
    ds.setStrings(["0.5", "0.5"], for: .pixelSpacing, vr: .DS)
    ds.setStrings(["1", "0", "0", "0", "1", "0"], for: .imageOrientationPatient, vr: .DS)
    ds.setStrings(["0", "0", "0"], for: .imagePositionPatient, vr: .DS)
    ds.setString("", for: .sliceThickness, vr: .DS)
    ds.setStrings(["ORIGINAL", "PRIMARY", "AXIAL"], for: .imageType, vr: .CS)
    ds.setString("0", for: .rescaleIntercept, vr: .DS)
    ds.setString("1", for: .rescaleSlope, vr: .DS)
    ds.setString("", for: .kvp, vr: .DS)
    ds.setString("", for: .acquisitionNumber, vr: .IS)
}

/// 8-bit MONOCHROME2, pixel[i] = fillPattern(i).
func makeGrayscale8(
    rows: UInt16, cols: UInt16,
    fillPattern: (Int) -> UInt8 = { UInt8($0 % 256) }
) -> DICOMFile {
    var ds = DataSet()
    ds.setString("1.2.840.10008.5.1.4.1.1.2", for: .sopClassUID, vr: .UI)
    ds.setString(rtUID(), for: .sopInstanceUID, vr: .UI)
    ds.setString("1.2.3.4.5.100", for: .studyInstanceUID, vr: .UI)
    ds.setString("1.2.3.4.5.200", for: .seriesInstanceUID, vr: .UI)
    ds.setString("CT", for: .modality, vr: .CS)
    ds.setString("RoundTrip^Patient", for: .patientName, vr: .PN)
    ds.setString("RT001", for: .patientID, vr: .LO)
    ds.setUInt16(rows, for: .rows)
    ds.setUInt16(cols, for: .columns)
    ds.setUInt16(8, for: .bitsAllocated)
    ds.setUInt16(8, for: .bitsStored)
    ds.setUInt16(7, for: .highBit)
    ds.setUInt16(0, for: .pixelRepresentation)
    ds.setUInt16(1, for: .samplesPerPixel)
    ds.setString("MONOCHROME2", for: .photometricInterpretation, vr: .CS)
    addCTImageModules(&ds)
    let count = Int(rows) * Int(cols)
    let pixels = Data((0..<count).map { fillPattern($0) })
    ds[.pixelData] = DataElement.data(tag: .pixelData, vr: .OB, data: pixels)
    return DICOMFile.create(dataSet: ds, sopClassUID: "1.2.840.10008.5.1.4.1.1.2")
}

/// 16-bit MONOCHROME2, unsigned (pixelRepresentation=0) or signed (=1).
func makeGrayscale16(
    rows: UInt16, cols: UInt16,
    fillPattern: (Int) -> UInt16 = { UInt16($0 % 65536) },
    signed: Bool = false
) -> DICOMFile {
    var ds = DataSet()
    ds.setString("1.2.840.10008.5.1.4.1.1.2", for: .sopClassUID, vr: .UI)
    ds.setString(rtUID(), for: .sopInstanceUID, vr: .UI)
    ds.setString("1.2.3.4.5.100", for: .studyInstanceUID, vr: .UI)
    ds.setString("1.2.3.4.5.200", for: .seriesInstanceUID, vr: .UI)
    ds.setString("CT", for: .modality, vr: .CS)
    ds.setString("RoundTrip^Patient", for: .patientName, vr: .PN)
    ds.setString("RT001", for: .patientID, vr: .LO)
    ds.setUInt16(rows, for: .rows)
    ds.setUInt16(cols, for: .columns)
    ds.setUInt16(16, for: .bitsAllocated)
    ds.setUInt16(16, for: .bitsStored)
    ds.setUInt16(15, for: .highBit)
    ds.setUInt16(signed ? 1 : 0, for: .pixelRepresentation)
    ds.setUInt16(1, for: .samplesPerPixel)
    ds.setString("MONOCHROME2", for: .photometricInterpretation, vr: .CS)
    addCTImageModules(&ds)
    let count = Int(rows) * Int(cols)
    var pixels = Data(count: count * 2)
    for i in 0..<count {
        let v = fillPattern(i)
        pixels[i * 2]     = UInt8(v & 0xFF)
        pixels[i * 2 + 1] = UInt8(v >> 8)
    }
    ds[.pixelData] = DataElement.data(tag: .pixelData, vr: .OW, data: pixels)
    return DICOMFile.create(dataSet: ds, sopClassUID: "1.2.840.10008.5.1.4.1.1.2")
}

/// 3-sample RGB, 8-bit.
func makeRGB8(rows: UInt16, cols: UInt16) -> DICOMFile {
    var ds = DataSet()
    ds.setString("1.2.840.10008.5.1.4.1.1.7", for: .sopClassUID, vr: .UI)
    ds.setString(rtUID(), for: .sopInstanceUID, vr: .UI)
    ds.setString("1.2.3.4.5.100", for: .studyInstanceUID, vr: .UI)
    ds.setString("1.2.3.4.5.200", for: .seriesInstanceUID, vr: .UI)
    ds.setString("OT", for: .modality, vr: .CS)
    ds.setUInt16(rows, for: .rows)
    ds.setUInt16(cols, for: .columns)
    ds.setUInt16(8, for: .bitsAllocated)
    ds.setUInt16(8, for: .bitsStored)
    ds.setUInt16(7, for: .highBit)
    ds.setUInt16(0, for: .pixelRepresentation)
    ds.setUInt16(3, for: .samplesPerPixel)
    ds.setString("RGB", for: .photometricInterpretation, vr: .CS)
    let count = Int(rows) * Int(cols) * 3
    let pixels = Data((0..<count).map { UInt8($0 % 256) })
    ds[.pixelData] = DataElement.data(tag: .pixelData, vr: .OB, data: pixels)
    return DICOMFile.create(dataSet: ds, sopClassUID: "1.2.840.10008.5.1.4.1.1.7")
}

/// Multi-frame 8-bit, each frame filled with `fill(frameIndex)` (default: index).
func makeMultiFrame(
    rows: UInt16, cols: UInt16, frames: Int,
    fill: (Int) -> UInt8 = { UInt8($0 % 256) }
) -> DICOMFile {
    var ds = DataSet()
    ds.setString("1.2.840.10008.5.1.4.1.1.2", for: .sopClassUID, vr: .UI)
    ds.setString(rtUID(), for: .sopInstanceUID, vr: .UI)
    ds.setString("1.2.3.4.5.100", for: .studyInstanceUID, vr: .UI)
    ds.setString("1.2.3.4.5.200", for: .seriesInstanceUID, vr: .UI)
    ds.setString("CT", for: .modality, vr: .CS)
    ds.setUInt16(rows, for: .rows)
    ds.setUInt16(cols, for: .columns)
    ds.setUInt16(8, for: .bitsAllocated)
    ds.setUInt16(8, for: .bitsStored)
    ds.setUInt16(7, for: .highBit)
    ds.setUInt16(0, for: .pixelRepresentation)
    ds.setUInt16(1, for: .samplesPerPixel)
    ds.setString("MONOCHROME2", for: .photometricInterpretation, vr: .CS)
    ds.setString("\(frames)", for: .numberOfFrames, vr: .IS)
    let frameSize = Int(rows) * Int(cols)
    var pixels = Data(count: frameSize * frames)
    for f in 0..<frames {
        let value = fill(f)
        for i in 0..<frameSize { pixels[f * frameSize + i] = value }
    }
    ds[.pixelData] = DataElement.data(tag: .pixelData, vr: .OB, data: pixels)
    return DICOMFile.create(dataSet: ds, sopClassUID: "1.2.840.10008.5.1.4.1.1.2")
}

// MARK: - Real anonymized corpus (Tier 2)

/// The 5 anonymized real DICOM files under Tests/DICOMRoundTripTest/Corpus/.
/// All have Patient Identity Removed = YES.
enum Corpus: String, CaseIterable {
    /// CT 512×512 16-bit MONOCHROME2, Explicit VR LE. WC 40 / WW 300,
    /// RescaleSlope 1 / Intercept -8192 (HU). PixelSpacing 0.72988671875.
    case ct = "CT.dcm"
    /// MR 384×384 16/12-bit MONOCHROME2, **Implicit VR LE** (1.2.840.10008.1.2).
    /// WC 538 / WW 1131. PixelSpacing 0.83333331346512.
    case mr = "MR.dcm"
    /// US 758×1016 8-bit YBR_FULL_422, **92-frame JPEG Baseline** (…1.2.4.50).
    case us = "US.dcm"
    /// CT 512×512 16-bit MONOCHROME2, **J2K lossless** (…1.2.4.90). WC 40 / WW 300.
    case j2kLossless = "j2klossless.dcm"
    /// Enhanced-MR 192×192 16/12-bit MONOCHROME2, **12-frame** Explicit VR LE.
    /// (Filename has no extension.) WC 2048 / WW 4096.
    case ctMultiframe = "CT_Multiframe"
}

/// Directory holding the corpus, resolved from this source file's location.
private var corpusDir: URL {
    URL(fileURLWithPath: #filePath)          // …/Tests/DICOMRoundTripTest/RoundTripFixture.swift
        .deletingLastPathComponent()          // …/Tests/DICOMRoundTripTest/
        .appendingPathComponent("Corpus")
}

/// URL of a corpus file, or `nil` if the corpus is not present (CI without corpus).
func corpusURL(_ file: Corpus) -> URL? {
    let url = corpusDir.appendingPathComponent(file.rawValue)
    return FileManager.default.fileExists(atPath: url.path) ? url : nil
}

/// Loads a corpus file as a parsed `DICOMFile`, or `nil` if absent.
/// Pair with `try XCTSkipIf(file == nil, "corpus absent")` at the top of a test.
func loadCorpus(_ file: Corpus) throws -> DICOMFile? {
    guard let url = corpusURL(file) else { return nil }
    return try DICOMFile.read(from: url, force: true)
}

// MARK: - I/O helpers

func writeTempDICOM(_ file: DICOMFile, name: String = "tmp.dcm") throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("DICOMRoundTrip-\(UUID().uuidString)")
        .appendingPathComponent(name)
    try FileManager.default.createDirectory(
        at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    let data = try file.write()
    try data.write(to: url)
    return url
}

func writeTempFile(_ data: Data, name: String) throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("DICOMRoundTrip-\(UUID().uuidString)-\(name)")
    try data.write(to: url)
    return url
}

func makeTempDir() throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("DICOMRoundTrip-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

func readJSONObject(at url: URL) throws -> [String: Any] {
    let data = try Data(contentsOf: url)
    return try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
}

func countFiles(in dir: URL, extension ext: String) -> Int {
    (try? FileManager.default.contentsOfDirectory(at: dir,
        includingPropertiesForKeys: nil))?.filter { $0.pathExtension == ext }.count ?? 0
}

// MARK: - Pixel access

/// Raw pixel bytes of the native (non-encapsulated) pixel data element.
func pixelBytes(_ file: DICOMFile) -> Data {
    file.dataSet[.pixelData]?.valueData ?? Data()
}

func readU8(_ data: Data, at i: Int) -> UInt8 { data[data.startIndex + i] }

func readU16(_ data: Data, at i: Int) -> UInt16 {
    let b = data.startIndex
    return UInt16(data[b + i * 2]) | (UInt16(data[b + i * 2 + 1]) << 8)
}

func readI16(_ data: Data, at i: Int) -> Int16 {
    Int16(bitPattern: readU16(data, at: i))
}

// MARK: - UID

/// Test-local UID generator (avoids clashing with library UIDGenerator internals).
func rtUID() -> String {
    "2.25.\(UInt64.random(in: 1_000_000_000_000_000_000...UInt64.max))"
}
