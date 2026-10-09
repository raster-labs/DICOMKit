//
// DICOMDIRProfileKeysTests.swift
// DICOMKitTests
//
// PS3.11 2026a "Additional DICOMDIR Keys" (Tables A.3-2, B.3-2, D.3-2, E.3-2, H.3-2, I.3-2; Annexes
// J, M and N apply H.3-2) and the Icon Images sections A.3.3.2 ("Directory Records of type IMAGE
// shall include Icon Images ... Bits Allocated (0028,0100) equal to 8 and Row (0028,0010) and
// Column (0028,0011) attribute values of 128"), B.3.3.2 (also Bits Stored 8 and MONOCHROME2) and
// E.3.3.3 (may, 64 x 64), within PS3.3 2026a F.7 (D239).
//

import XCTest
@testable import DICOMKit
@testable import DICOMCore

final class DICOMDIRProfileKeysTests: XCTestCase {

    private var counter = 0
    private func uid() -> String {
        counter += 1
        return "1.2.826.0.1.3680043.10.1078.88.\(counter)"
    }

    private let xa = "1.2.840.10008.5.1.4.1.1.12.1"
    private let sc = "1.2.840.10008.5.1.4.1.1.7"
    private let mr = "1.2.840.10008.5.1.4.1.1.4"
    private let jpegLosslessSV1 = "1.2.840.10008.1.2.4.70"

    /// An 8-bit MONOCHROME2 image whose value is the column scaled to 0...255.
    private func image(_ sop: String, ts: String = "1.2.840.10008.1.2.1", rows: Int = 128, columns: Int = 256,
                       modality: String, series: String = "1.2.3.200.1",
                       _ extra: (inout DataSet) -> Void = { _ in }) -> DICOMFile {
        var ds = DataSet()
        let instanceUID = uid()
        ds.setString(sop, for: .sopClassUID, vr: .UI)
        ds.setString(instanceUID, for: .sopInstanceUID, vr: .UI)
        ds.setString("1.2.3.200", for: .studyInstanceUID, vr: .UI)
        ds.setString(series, for: .seriesInstanceUID, vr: .UI)
        ds.setString("P1", for: .patientID, vr: .LO)
        ds.setString("Doe^Jane", for: .patientName, vr: .PN)
        ds.setString(modality, for: .modality, vr: .CS)
        ds.setString("20240115", for: .studyDate, vr: .DA)
        ds.setString("101500", for: .studyTime, vr: .TM)
        ds.setUInt16(UInt16(rows), for: .rows)
        ds.setUInt16(UInt16(columns), for: .columns)
        ds.setUInt16(1, for: .samplesPerPixel)
        ds.setString("MONOCHROME2", for: .photometricInterpretation, vr: .CS)
        ds.setUInt16(8, for: .bitsAllocated)
        ds.setUInt16(8, for: .bitsStored)
        ds.setUInt16(7, for: .highBit)
        ds.setUInt16(0, for: .pixelRepresentation)
        var pixels = Data(count: rows * columns)
        for r in 0..<rows { for c in 0..<columns { pixels[r * columns + c] = UInt8(c * 255 / max(1, columns - 1)) } }
        ds[.pixelData] = DataElement.data(tag: .pixelData, vr: .OB, data: ts == jpegLosslessSV1 ? Data(count: 2) : pixels)
        extra(&ds)
        return DICOMFile.create(dataSet: ds, sopClassUID: sop, sopInstanceUID: instanceUID, transferSyntaxUID: ts)
    }

    private func icon(rows: Int = 128, columns: Int = 128, pi: String = "MONOCHROME2") -> [SequenceItem] {
        var icon = DataSet()
        icon.setUInt16(1, for: .samplesPerPixel)
        icon.setString(pi, for: .photometricInterpretation, vr: .CS)
        icon.setUInt16(UInt16(rows), for: .rows)
        icon.setUInt16(UInt16(columns), for: .columns)
        icon.setUInt16(8, for: .bitsAllocated)
        icon.setUInt16(8, for: .bitsStored)
        icon.setUInt16(7, for: .highBit)
        icon.setUInt16(0, for: .pixelRepresentation)
        icon[.pixelData] = DataElement.data(tag: .pixelData, vr: .OB, data: Data(repeating: 0x7F, count: rows * columns))
        return [SequenceItem(elements: icon.allElements)]
    }

    private func fileID(_ n: Int) -> [String] { ["DICOM", "IM\(n)"] }

    private func refusal(_ body: () throws -> Void) -> DICOMDIRProfileRules.Refusal? {
        do { try body(); return nil } catch { return error as? DICOMDIRProfileRules.Refusal }
    }

    // MARK: - Which table each profile applies

    func testAdditionalKeyTablePerProfile() {
        let expected: [(DICOMDIRProfile, String?)] = [
            (.standardXABasicCardiacCD, "A.3-2"), (.standardXA1024CD, "B.3-2"), (.standardXA1024DVD, "B.3-2"),
            (.standardGeneralCD, "D.3-2"), (.standardGeneralBD, "D.3-2"), (.standardCTMRCD, "E.3-2"),
            (.standardGeneralMIME, nil), (.standardGeneralDVDJPEG, "H.3-2"), (.standardDVDMPEG2MPML, "I.3-2"),
            (.standardGeneralUSBJPEG, "H.3-2"), (.standardDentalCD, nil),
            (DICOMDIRProfile(rawValue: "STD-GEN-BD-JPEG")!, "H.3-2"),
            (.ultrasound(.imageDisplay, frames: false, media: .cdr), nil),
        ]
        for (profile, label) in expected {
            XCTAssertEqual(DICOMDIRProfileRules.additionalKeyTableLabel(for: profile), label, profile.rawValue)
        }
        XCTAssertEqual(DICOMDIRProfileRules.additionalKeyTables["H.3-2"]?.count, 19)
        let icon = DICOMDIRProfileRules.iconImageRules["B"]
        XCTAssertEqual(icon?.rows, 128)
        XCTAssertEqual(icon?.photometricInterpretations, ["MONOCHROME2"])
        XCTAssertEqual(DICOMDIRProfileRules.iconImageRules["A"]?.required, true)
        XCTAssertEqual(DICOMDIRProfileRules.iconImageRules["E"]?.required, false)
    }

    // MARK: - STD-XA1K: generated icon, Type 2 keys

    func testXA1KSecondaryCaptureGetsAGeneratedIconAndType2Keys() throws {
        var builder = DICOMDirectory.Builder(fileSetID: "XA1K", profile: .standardXA1024CD)
        try builder.addFile(image(sc, modality: "OT") { ds in
            ds.setString("19700101", for: .patientBirthDate, vr: .DA)
            ds.setString("F", for: .patientSex, vr: .CS)
            ds.setString("General Hospital", for: .institutionName, vr: .LO)
        }, relativePath: fileID(1))
        let directory = builder.build()
        let patient = try XCTUnwrap(directory.rootRecords.first)
        XCTAssertEqual(patient.attribute(for: .patientBirthDate)?.stringValue, "19700101")
        XCTAssertEqual(patient.attribute(for: .patientSex)?.stringValue?.trimmingCharacters(in: .whitespaces), "F")
        let series = try XCTUnwrap(patient.children.first?.children.first)
        XCTAssertEqual(series.attribute(for: .institutionName)?.stringValue?.trimmingCharacters(in: .whitespaces), "General Hospital")
        XCTAssertEqual(series.attribute(for: .institutionAddress)?.length, 0, "Type 2: zero length when unknown")
        XCTAssertEqual(series.attribute(for: Tag(group: 0x0008, element: 0x1050))?.length, 0)
        let leaf = try XCTUnwrap(series.children.first)
        XCTAssertEqual(leaf.attribute(for: Tag(group: 0x0050, element: 0x0004))?.length, 0, "Calibration Image Type 2")

        let item = try XCTUnwrap(leaf.attribute(for: .iconImageSequence)?.sequenceItems?.first)
        XCTAssertEqual(leaf.attribute(for: .iconImageSequence)?.sequenceItems?.count, 1)
        XCTAssertEqual(DICOMDIRProfileRules.iconProblems(item, rule: try XCTUnwrap(DICOMDIRProfileRules.iconImageRules["B"])), [])
        let pixels = [UInt8](try XCTUnwrap(item[.pixelData]?.valueData))
        XCTAssertEqual(pixels.count, 128 * 128)
        // 256 x 128 fitted to 128 x 64, centred: rows 0..<32 and 96..<128 black
        XCTAssertEqual(pixels[10 * 128 + 64], 0)
        XCTAssertEqual(pixels[110 * 128 + 64], 0)
        XCTAssertLessThan(pixels[64 * 128 + 0], 5)
        XCTAssertGreaterThan(pixels[64 * 128 + 127], 250)

        // The icon survives the DICOMDIR write / read
        let read = try DICOMDIRReader.read(from: try DICOMDIRWriter.write(directory))
        let readLeaf = try XCTUnwrap(read.rootRecords.first?.children.first?.children.first?.children.first)
        XCTAssertEqual(readLeaf.attribute(for: .iconImageSequence)?.sequenceItems?.first?[.pixelData]?.valueData.count, 128 * 128)
    }

    // MARK: - STD-XABC-CD: XA keys

    func testXABCCopiesAConformingIconAndRequiresImageType() throws {
        var builder = DICOMDirectory.Builder(fileSetID: "XABC", profile: .standardXABasicCardiacCD)
        let own = icon()
        try builder.addFile(image(xa, ts: jpegLosslessSV1, rows: 512, columns: 512, modality: "XA") { ds in
            ds.setStrings(["ORIGINAL", "PRIMARY", "SINGLE PLANE"], for: .imageType, vr: .CS)
            ds.setSequence(own, for: .iconImageSequence)
        }, relativePath: fileID(1))
        let leaf = try XCTUnwrap(builder.build().rootRecords.first?.children.first?.children.first?.children.first)
        XCTAssertEqual(leaf.attribute(for: .iconImageSequence)?.sequenceItems?.first?[.pixelData]?.valueData,
                       own.first?[.pixelData]?.valueData)
        XCTAssertEqual(leaf.attribute(for: .imageType)?.stringValues?.last, "SINGLE PLANE")

        // Image Type is Type 1 in A.3-2
        let missingImageType = refusal {
            try builder.addFile(image(xa, ts: jpegLosslessSV1, rows: 512, columns: 512, modality: "XA") { ds in
                ds.setSequence(own, for: .iconImageSequence)
            }, relativePath: fileID(2))
        }
        guard case .missingProfileKey(_, "IMAGE", "Image Type", _, "A.3-2", _)? = missingImageType else {
            return XCTFail("\(String(describing: missingImageType))")
        }
    }

    func testXABCRefusesAnInstanceWhoseIconCannotBeMade() {
        var builder = DICOMDirectory.Builder(fileSetID: "XABC", profile: .standardXABasicCardiacCD)
        // 64 x 64 icon: not the 128 x 128 of A.3.3.2; the JPEG data is not decodable
        let result = refusal {
            try builder.addFile(image(xa, ts: jpegLosslessSV1, rows: 512, columns: 512, modality: "XA") { ds in
                ds.setStrings(["ORIGINAL", "PRIMARY", "SINGLE PLANE"], for: .imageType, vr: .CS)
                ds.setSequence(icon(rows: 64, columns: 64), for: .iconImageSequence)
            }, relativePath: fileID(1))
        }
        guard case .missingProfileKey(let profile, "IMAGE", "Icon Image Sequence", "(0088,0200)", "A.3-2", let reason)? = result else {
            return XCTFail("\(String(describing: result))")
        }
        XCTAssertEqual(profile, "STD-XABC-CD")
        XCTAssertTrue(reason.contains("A.3.3.2"), reason)
        XCTAssertTrue("\(result!)".contains("[PS3.11 2026a Table A.3-2]"), "\(result!)")
        XCTAssertTrue(builder.build().rootRecords.isEmpty, "a refused instance leaves the directory unchanged")
    }

    func testBiplaneRequiresReferencedImageSequence() {
        var builder = DICOMDirectory.Builder(fileSetID: "XABC", profile: .standardXABasicCardiacCD)
        let result = refusal {
            try builder.addFile(image(xa, ts: jpegLosslessSV1, rows: 512, columns: 512, modality: "XA") { ds in
                ds.setStrings(["ORIGINAL", "PRIMARY", "BIPLANE A"], for: .imageType, vr: .CS)
                ds.setSequence(self.icon(), for: .iconImageSequence)
            }, relativePath: fileID(1))
        }
        guard case .missingProfileKey(_, _, "Referenced Image Sequence", _, "A.3-2", _)? = result else {
            return XCTFail("\(String(describing: result))")
        }
    }

    // MARK: - STD-CTMR: localizer keys and Rows / Columns (E.3.3.2)

    func testCTMRImageRecordCarriesImagePlaneKeys() throws {
        var builder = DICOMDirectory.Builder(fileSetID: "CTMR", profile: .standardCTMRCD)
        try builder.addFile(image(mr, modality: "MR") { ds in
            ds.setStrings(["0", "0", "10"], for: .imagePositionPatient, vr: .DS)
            ds.setStrings(["1", "0", "0", "0", "1", "0"], for: .imageOrientationPatient, vr: .DS)
            ds.setString("1.2.3.200.9", for: .frameOfReferenceUID, vr: .UI)
            ds.setStrings(["0.5", "0.5"], for: .pixelSpacing, vr: .DS)
        }, relativePath: fileID(1))
        let leaf = try XCTUnwrap(builder.build().rootRecords.first?.children.first?.children.first?.children.first)
        XCTAssertEqual(leaf.attribute(for: .rows)?.uint16Value, 128)
        XCTAssertEqual(leaf.attribute(for: .columns)?.uint16Value, 256)
        XCTAssertEqual(leaf.attribute(for: .frameOfReferenceUID)?.stringValue?.trimmingCharacters(in: .init(charactersIn: "\0")), "1.2.3.200.9")
        XCTAssertEqual(leaf.attribute(for: .imageOrientationPatient)?.stringValues?.count, 6)
        XCTAssertNotNil(leaf.attribute(for: .imagePositionPatient))
        XCTAssertNotNil(leaf.attribute(for: .pixelSpacing))
        XCTAssertNil(leaf.attribute(for: .iconImageSequence), "E.3.3.3: icons may be included; none is generated")
    }

    // MARK: - STD-GEN-DVD-JPEG (H.3-2): subordinate-record keys, Shared Functional Groups

    func testH32KeysFromSubordinateObjectsAndSharedFunctionalGroups() throws {
        var builder = DICOMDirectory.Builder(fileSetID: "DVD", profile: .standardGeneralDVDJPEG)
        try builder.addFile(image(sc, modality: "OT"), relativePath: fileID(1))
        try builder.addFile(image(sc, modality: "OT") { ds in
            ds.setString("General Hospital", for: .institutionName, vr: .LO)
            ds.setString("M", for: .patientSex, vr: .CS)
            var measures = DataSet()
            measures.setStrings(["0.25", "0.25"], for: .pixelSpacing, vr: .DS)
            var group = DataSet()
            group.setSequence([SequenceItem(elements: measures.allElements)], for: Tag(group: 0x0028, element: 0x9110))
            ds.setSequence([SequenceItem(elements: group.allElements)], for: .sharedFunctionalGroupsSequence)
        }, relativePath: fileID(2))
        let patient = try XCTUnwrap(builder.build().rootRecords.first)
        XCTAssertEqual(patient.attribute(for: .patientSex)?.stringValue?.trimmingCharacters(in: .whitespaces), "M",
                       "1C: present in an object referenced by a subordinate record")
        let series = try XCTUnwrap(patient.children.first?.children.first)
        XCTAssertEqual(series.attribute(for: .institutionName)?.stringValue?.trimmingCharacters(in: .whitespaces), "General Hospital")
        XCTAssertNil(series.attribute(for: .institutionAddress), "1C, absent everywhere: not written")
        XCTAssertEqual(series.children.count, 2)
        XCTAssertNil(series.children[0].attribute(for: .pixelSpacing))
        XCTAssertEqual(series.children[1].attribute(for: .pixelSpacing)?.stringValues?.first?.trimmingCharacters(in: .whitespaces), "0.25")
        XCTAssertEqual(series.children[1].attribute(for: .rows)?.uint16Value, 128, "Rows Type 1 (H.3-2)")
    }

    func testH32RowsAreType1() {
        var builder = DICOMDirectory.Builder(fileSetID: "DVD", profile: .standardGeneralUSBJPEG)
        let result = refusal {
            try builder.addFile(image(sc, modality: "OT") { ds in ds.remove(tag: .rows) }, relativePath: fileID(1))
        }
        guard case .missingProfileKey(_, "IMAGE", "Rows", _, "H.3-2", _)? = result else {
            return XCTFail("\(String(describing: result))")
        }
    }

    // MARK: - Icon pixels (PS3.3 F.7)

    func testIconPixelsInvertMonochrome1AndUseTheWindow() throws {
        let rule = DICOMDIRProfileRules.IconImageRule(section: "T", recordTypes: ["IMAGE"], required: true,
                                                     rows: 4, columns: 4, bits: 8, photometricInterpretations: [])
        let mono1 = image(sc, rows: 4, columns: 4, modality: "OT") { ds in
            ds.setString("MONOCHROME1", for: .photometricInterpretation, vr: .CS)
        }
        let inverted = try DICOMDIRProfileRules.iconPixels(from: mono1, rows: 4, columns: 4)
        XCTAssertEqual(inverted[0], 255)
        XCTAssertEqual(inverted[3], 0)
        // Window Center 128 / Width 2: everything above 128 white, below black
        let windowed = image(sc, rows: 4, columns: 4, modality: "OT") { ds in
            ds.setString("128", for: .windowCenter, vr: .DS)
            ds.setString("2", for: .windowWidth, vr: .DS)
        }
        let pixels = try DICOMDIRProfileRules.iconPixels(from: windowed, rows: 4, columns: 4)
        XCTAssertEqual(pixels[0], 0)
        XCTAssertEqual(pixels[3], 255)
        let sequence = try DICOMDIRProfileRules.iconImageSequence(for: windowed, rule: rule)
        let item = try XCTUnwrap(sequence.sequenceItems?.first)
        XCTAssertEqual(DICOMDIRProfileRules.iconProblems(item, rule: rule), [])
        XCTAssertNil(item[.planarConfiguration])
        XCTAssertNil(item[.pixelAspectRatio])
    }
}
