// NEMA-verified: 2026a, checked 2026-10-06 — Media Storage SOP Instance UID (0002,0003) identifies the SOP Instance of the Data Set (PS3.10 2026a Table 7.1-1); Specific Character Set (0008,0005) Type 1C, ISO_IR 192 = Unicode in UTF-8 (PS3.3 2026a Table C.12-1, C.12-5); Conversion Type Defined Terms (Table C.8-24); LO / PN / UI / IS limits (PS3.5 2026a Table 6.2-1, 9.1) (D274); Study Date / Time Type 2 "Date / Time the Study started" (PS3.3 2026a Table C.7-3), DA Gregorian YYYYMMDD and TM HHMMSS.FFFFFF (PS3.5 Table 6.2-1), Instance Creation Date / Time (Table C.12-1), Date / Time of Secondary Capture (Table C.8-25) (P-IMAGE-STUDY-DATETIME)
import XCTest
@testable import DICOMKit
import DICOMCore
#if canImport(CoreGraphics)
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
#endif

/// D274: the dicom-image output rules live in `ImageConverter.OutputRules`, and the engine's own
/// output already satisfies them, so no caller has to post-process.
final class ImageConverterOutputRulesTests: XCTestCase {

    #if canImport(CoreGraphics)
    private func writePNG(to url: URL) throws {
        let width = 4, height = 3
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        for i in 0..<(width * height) { bytes[i * 4] = UInt8(i * 20); bytes[i * 4 + 3] = 255 }
        let ctx = try XCTUnwrap(CGContext(data: &bytes, width: width, height: height, bitsPerComponent: 8,
                                          bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        let image = try XCTUnwrap(ctx.makeImage())
        let dest = try XCTUnwrap(CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(dest, image, nil)
        XCTAssertTrue(CGImageDestinationFinalize(dest))
    }

    /// The engine writes one UID for (0002,0003) and (0008,0018), and ISO_IR 192 for non-ASCII
    /// text, without `finalize`; `finalize` on its output changes no byte.
    func testEngineOutputNeedsNoPostProcessing() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("ic-\(UUID().uuidString).png")
        defer { try? FileManager.default.removeItem(at: url) }
        try writePNG(to: url)
        for (name, charset) in [("Müller^Jörg", "ISO_IR 192"), ("DOE^JOHN", nil)] {
            let meta = ImageConverter.Metadata(patientName: name, patientID: "P1", studyUID: "1.2.3",
                                               seriesUID: "1.2.3.4", instanceNumber: 1)
            let data = try ImageConverter.secondaryCaptureData(imageURL: url, metadata: meta, useExif: false)
            let file = try DICOMFile.read(from: data)
            let sop = try XCTUnwrap(file.dataSet.string(for: .sopInstanceUID))
            XCTAssertEqual(file.fileMetaInformation.string(for: .mediaStorageSOPInstanceUID), sop, "PS3.10 Table 7.1-1")
            XCTAssertEqual(file.fileMetaInformation.string(for: .mediaStorageSOPClassUID),
                           file.dataSet.string(for: .sopClassUID))
            XCTAssertEqual(file.dataSet.string(for: .specificCharacterSet), charset, name)
            XCTAssertEqual(try ImageConverter.OutputRules.finalize(data), data, "finalize is a no-op on engine output")
        }
    }

    /// Study Date / Time come from Metadata (empty when nil, Type 2); the conversion moment is
    /// Instance Creation Date / Time and Date / Time of Secondary Capture.
    func testStudyAndConversionDateTimeAreWritten() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("ic-\(UUID().uuidString).png")
        defer { try? FileManager.default.removeItem(at: url) }
        try writePNG(to: url)
        let moment = Date(timeIntervalSince1970: 1_790_000_000)
        let date = ImageConverter.OutputRules.localDate(moment).dicomString
        let time = ImageConverter.OutputRules.localTime(moment).dicomString
        var meta = ImageConverter.Metadata(patientName: "DOE^JOHN", patientID: "P1", studyUID: "1.2.3",
                                           seriesUID: "1.2.3.4", instanceNumber: 1,
                                           studyDate: DICOMDate(year: 2026, month: 9, day: 15),
                                           studyTime: DICOMTime(hour: 9, minute: 30, second: 0),
                                           conversionDate: moment)
        var ds = try DICOMFile.read(from: ImageConverter.secondaryCaptureData(imageURL: url, metadata: meta, useExif: false)).dataSet
        XCTAssertEqual(ds.string(for: .studyDate), "20260915")
        XCTAssertEqual(ds.string(for: .studyTime), "093000")
        for (tag, value) in [(Tag.instanceCreationDate, date), (.instanceCreationTime, time),
                             (.dateOfSecondaryCapture, date), (.timeOfSecondaryCapture, time)] {
            XCTAssertEqual(ds.string(for: tag), value, "\(tag)")
        }
        meta.studyDate = nil
        meta.studyTime = nil
        ds = try DICOMFile.read(from: ImageConverter.secondaryCaptureData(imageURL: url, metadata: meta, useExif: false)).dataSet
        XCTAssertNotNil(ds[.studyDate], "Type 2: present")
        XCTAssertNotNil(ds[.studyTime], "Type 2: present")
        XCTAssertEqual(ds.string(for: .studyDate) ?? "", "")
        XCTAssertEqual(ds.string(for: .studyTime) ?? "", "")
    }
    #endif

    /// --study-date / --study-time accept only the PS3.5 Table 6.2-1 DA / TM forms; the run's
    /// Study Date / Time follow the three cases of `studyDateTime`.
    func testStudyDateTimeRules() {
        let rules = ImageConverter.OutputRules.self
        for good in ["20260915", "20240229", "19000101"] { XCTAssertNotNil(rules.studyDate(good), good) }
        for bad in ["2026-09-15", "2026.09.15", "20250229", "20261301", "20260931", "2026091", " 20260915", "２0260915"] {
            XCTAssertNil(rules.studyDate(bad), bad)
        }
        for good in ["09", "0930", "093000", "093000.5", "235960.123456"] { XCTAssertNotNil(rules.studyTime(good), good) }
        for bad in ["9", "093", "24", "0960", "093061", "09:30", "0930.5", "093000.", "093000.1234567", "093000 "] {
            XCTAssertNil(rules.studyTime(bad), bad)
        }
        let lines = rules.valueViolations(patientName: nil, patientID: nil, studyDescription: nil, seriesDescription: nil,
                                          studyUID: nil, seriesUID: nil, seriesNumber: nil, instanceNumber: nil,
                                          studyDate: "2026-09-15", studyTime: "25")
        XCTAssertEqual(lines.count, 2, lines.joined(separator: "\n"))
        XCTAssertTrue(lines[0].hasPrefix("--study-date '2026-09-15' is not a DA value"))
        XCTAssertTrue(lines[1].hasPrefix("--study-time '25' is not a TM value"))

        let run = Date(timeIntervalSince1970: 1_790_000_000)
        let fresh = rules.studyDateTime(studyDate: nil, studyTime: nil, studyUID: nil, runDate: run)
        XCTAssertEqual(fresh.date, rules.localDate(run), "new Study: the run's date")
        XCTAssertEqual(fresh.time, rules.localTime(run), "new Study: the run's time")
        let existing = rules.studyDateTime(studyDate: nil, studyTime: nil, studyUID: "1.2.3", runDate: run)
        XCTAssertNil(existing.date, "--study-uid: unknown start, written empty")
        XCTAssertNil(existing.time)
        let given = rules.studyDateTime(studyDate: "20260915", studyTime: nil, studyUID: nil, runDate: run)
        XCTAssertEqual(given.date?.dicomString, "20260915")
        XCTAssertNil(given.time, "only the given value is written")
    }

    /// DA is "a date of the Gregorian calendar system" whatever calendar the system uses.
    func testLocalDateIsGregorian() {
        let moment = Date(timeIntervalSince1970: 1_790_000_000)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        XCTAssertEqual(ImageConverter.OutputRules.localDate(moment).year, calendar.component(.year, from: moment))
    }

    /// `finalize` repairs a file from elsewhere: a stale (0002,0003) and non-ASCII text in a
    /// Sequence Item with no Specific Character Set.
    func testFinalizeRepairsAForeignFile() throws {
        var item = DataSet()
        item.setString("Zoë", for: .codeMeaning, vr: .LO)
        var ds = DataSet()
        ds.setString("1.2.840.10008.5.1.4.1.1.7", for: .sopClassUID, vr: .UI)
        ds.setString("1.2.3.4.5", for: .sopInstanceUID, vr: .UI)
        ds.setSequence([SequenceItem(elements: Array(item))], for: .conceptNameCodeSequence)
        var meta = DICOMFile.create(dataSet: ds).fileMetaInformation
        meta.setString("1.2.3.4.999", for: .mediaStorageSOPInstanceUID, vr: .UI)
        meta.remove(tag: .fileMetaInformationGroupLength)
        let data = try DICOMFile(fileMetaInformation: meta, dataSet: ds).write()
        let after = try DICOMFile.read(from: ImageConverter.OutputRules.finalize(data))
        XCTAssertEqual(after.fileMetaInformation.string(for: .mediaStorageSOPInstanceUID), "1.2.3.4.5")
        XCTAssertEqual(after.dataSet.string(for: .specificCharacterSet), ImageConverter.OutputRules.utf8CharacterSet)
        XCTAssertEqual(ImageConverter.OutputRules.utf8CharacterSet, "ISO_IR 192")
    }

    func testConversionTypeAndValueRefusals() {
        XCTAssertEqual(ImageConverter.OutputRules.conversionType(nil), .workstation)
        XCTAssertEqual(ImageConverter.OutputRules.conversionType(" drw ")?.rawValue, "DRW")
        XCTAssertNil(ImageConverter.OutputRules.conversionType("XYZ"))
        XCTAssertTrue(ImageConverter.OutputRules.valueViolations(
            patientName: "DOE^JOHN", patientID: "P1", studyDescription: nil, seriesDescription: nil,
            studyUID: "1.2.3", seriesUID: nil, seriesNumber: 1, instanceNumber: 1).isEmpty)
        let lines = ImageConverter.OutputRules.valueViolations(
            patientName: String(repeating: "A", count: 65), patientID: "a\\b",
            studyDescription: String(repeating: "x", count: 65), seriesDescription: nil,
            studyUID: "1.02.3", seriesUID: nil, seriesNumber: Int(Int32.max) + 1, instanceNumber: nil)
        XCTAssertEqual(lines.count, 5, lines.joined(separator: "\n"))
        XCTAssertTrue(lines.contains { $0.hasPrefix("--study-uid '1.02.3' is not a valid UID (PS3.5 9.1") })
        XCTAssertTrue(lines.contains("--patient-id contains a backslash, which LO does not allow (PS3.5 Table 6.2-1)"))
    }
}
