import Testing
import Foundation
@testable import DICOMWeb

/// Locks the shared `QIDOResultFormatter` rendering. This is the SINGLE formatter
/// the `dicom-wado query` CLI and the CLI Workshop's in-app query both call, so these
/// expectations are exactly what the CLI prints — a drift here is a real app↔CLI
/// divergence (the bug that motivated the shared formatter: the app used to ignore
/// `--format table` and dump a verbose per-record block instead of the table).
@Suite("QIDOResultFormatter")
struct QIDOResultFormatterTests {

    private func study() -> QIDOStudyResult {
        QIDOStudyResult(attributes: [
            "0020000D": ["vr": "UI", "Value": ["1.2.3"]],
            "00100010": ["vr": "PN", "Value": [["Alphabetic": "DOE^JOHN"]]],
            "00100020": ["vr": "LO", "Value": ["P1"]],
            "00080020": ["vr": "DA", "Value": ["20240101"]],
            "00081030": ["vr": "LO", "Value": ["CHEST"]],
            "00080061": ["vr": "CS", "Value": ["CT"]],
            "00201206": ["vr": "IS", "Value": [2]],
        ])
    }

    @Test("Study table reproduces the CLI's bordered table")
    func studyTable() {
        let out = QIDOResultFormatter().formatStudies([study()], format: .table)
        let lines = out.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        // Header + one data row between three 120-wide "=" borders (the format the
        // CLIParityWADOComparator.count(in:format:) parser depends on).
        #expect(lines[0] == String(repeating: "=", count: 120))
        #expect(lines[1].hasPrefix("Study Instance UID"))
        #expect(lines[1].contains("Patient's Name"))
        #expect(lines[1].contains("Number of Study Related Series"))
        #expect(lines[2] == String(repeating: "=", count: 120))
        #expect(lines[3].hasPrefix("1.2.3"))
        #expect(lines[3].contains("DOE^JOHN"))
        #expect(lines[3].contains("20240101"))
        #expect(lines[3].contains("CT"))
        #expect(lines[4] == String(repeating: "=", count: 120))
    }

    @Test("Study CSV header + row match the CLI exactly")
    func studyCSV() {
        let out = QIDOResultFormatter().formatStudies([study()], format: .csv)
        let lines = out.split(separator: "\n").map(String.init)
        #expect(lines[0] == "StudyInstanceUID,PatientName,PatientID,StudyDate,StudyDescription,ModalitiesInStudy,NumberOfSeries")
        #expect(lines[1] == "1.2.3,DOE^JOHN,P1,20240101,CHEST,CT,2")
    }

    @Test("Study JSON is pretty-printed with sorted keys")
    func studyJSON() {
        let out = QIDOResultFormatter().formatStudies([study()], format: .json)
        // Valid JSON array carrying the study's attributes.
        let data = out.data(using: .utf8)!
        let arr = try! JSONSerialization.jsonObject(with: data) as! [[String: Any]]
        #expect(arr.count == 1)
        #expect(arr[0]["StudyInstanceUID"] as? String == "1.2.3")
        #expect(arr[0]["PatientName"] as? String == "DOE^JOHN")
        #expect(arr[0]["NumberOfStudyRelatedSeries"] as? Int == 2)
        // sortedKeys → PatientID sorts before StudyInstanceUID in the emitted text.
        #expect(out.range(of: "PatientID")!.lowerBound < out.range(of: "StudyInstanceUID")!.lowerBound)
    }

    @Test("Empty study set still prints the bordered (header-only) table, like the CLI")
    func emptyStudyTable() {
        let out = QIDOResultFormatter().formatStudies([], format: .table)
        let lines = out.split(separator: "\n", omittingEmptySubsequences: false).filter { !$0.isEmpty }
        // Top border + header + mid border + bottom border (no data rows), and crucially
        // no "No results" sentinel — the QIDO CLI prints the empty table, unlike the
        // DIMSE formatter which prints "No results found.".
        #expect(lines.count == 4)
        #expect(!out.contains("No results"))
    }

    // MARK: - D105: column labels are the PS3.6 2026a Table 6-1 Attribute Names

    @Test("D105: study table labels are PS3.6 Table 6-1 names (Modalities in Study, Number of Study Related Series)")
    func studyLabelsArePS36Names() {
        let header = QIDOResultFormatter().formatStudies([study()], format: .table)
            .split(separator: "\n").map(String.init)[1]
        for name in ["Study Instance UID", "Patient's Name", "Study Date",
                     "Modalities in Study", "Number of Study Related Series"] {
            #expect(header.contains(name), "missing \(name)")
        }
        #expect(!header.contains("# Series"))
        #expect(!header.contains(" Modality "))
    }

    @Test("D105: series table says Number of Series Related Instances (0020,1209), not # Images")
    func seriesLabelsArePS36Names() {
        let series = QIDOSeriesResult(attributes: [
            "0020000E": ["vr": "UI", "Value": ["1.2.3.4"]],
            "00080060": ["vr": "CS", "Value": ["MR"]],
            "0008103E": ["vr": "LO", "Value": ["AX T1"]],
            "00201209": ["vr": "IS", "Value": [7]],
        ])
        let lines = QIDOResultFormatter().formatSeries([series], format: .table)
            .split(separator: "\n").map(String.init)
        for name in ["Series Instance UID", "Modality", "Series Description",
                     "Number of Series Related Instances"] {
            #expect(lines[1].contains(name), "missing \(name)")
        }
        #expect(!lines[1].contains("# Images"))
        #expect(lines[3].contains("MR"))
        #expect(lines[3].contains("7"))
    }

    @Test("D105: instance table prints the whole SOP Class UID under PS3.6 names")
    func instanceSOPClassUIDNotTruncated() {
        let uid = "1.2.840.10008.5.1.4.1.1.88.33" // Comprehensive SR Storage, 29 chars
        let instance = QIDOInstanceResult(attributes: [
            "00080018": ["vr": "UI", "Value": ["9.8.7"]],
            "00080016": ["vr": "UI", "Value": [uid]],
            "00280008": ["vr": "IS", "Value": [3]],
        ])
        let lines = QIDOResultFormatter().formatInstances([instance], format: .table)
            .split(separator: "\n").map(String.init)
        #expect(lines[1].contains("SOP Instance UID"))
        #expect(lines[1].contains("SOP Class UID"))
        #expect(lines[1].contains("Number of Frames"))
        #expect(!lines[1].contains("# Frames"))
        #expect(lines[3].contains(uid))
        #expect(!lines[3].contains("..."))
    }
}
