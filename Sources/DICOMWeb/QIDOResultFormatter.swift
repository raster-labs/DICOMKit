import Foundation

// NEMA-verified: 2026a, checked 2026-10-01 — the 12 table column labels are the PS3.6 2026a Table 6-1 Attribute Names of the attributes shown (12 rows dumped by Scripts/nema_docbook.py; D105); UIDs are printed whole (SOP Class UID no longer truncated); JSON keys are Table 6-1 Keywords
/// Output renderings shared by the `dicom-wado query` CLI (QIDO-RS) and
/// DICOMStudio's in-app QIDO query, so both produce identical text for the same
/// search results. This mirrors `DICOMQueryResultFormatter` (DICOMNetwork) for the
/// DIMSE C-FIND tools: a SINGLE formatter both sides call, so their output pipelines
/// cannot drift (the app previously hand-rolled a divergent renderer that ignored
/// `--format table` and emitted a verbose per-record dump instead of the CLI's table).
public enum QIDOOutputFormat: String, Sendable, CaseIterable {
    case table
    /// A tool summary keyed by PS3.6 keyword (not the DICOM JSON Model).
    case json
    case csv
    /// The PS3.18 2026a F.2 DICOM JSON Model: the result's attributes as the origin
    /// server returned them (tag keys, `vr`, `Value`), via `DICOMJSONModelFormatter`.
    case dicomJSON = "dicom-json"
}

/// Renders QIDO-RS study / series / instance results to text. The only QIDO output
/// formatter in the codebase — used by both the `dicom-wado` CLI and the CLI Workshop.
public struct QIDOResultFormatter {
    public init() {}

    // MARK: - Study

    public func formatStudies(_ studies: [QIDOStudyResult], format: QIDOOutputFormat) -> String {
        switch format {
        case .table: return studyTable(studies)
        case .json:  return formatJSON(studies.map(studyDict))
        case .csv:   return studyCSV(studies)
        case .dicomJSON: return DICOMJSONModelFormatter.format(studies.map(\.attributes))
        }
    }

    private func studyTable(_ studies: [QIDOStudyResult]) -> String {
        var output = ""
        output += String(repeating: "=", count: 120) + "\n"
        // Column labels are the PS3.6 2026a Table 6-1 Attribute Names (D105).
        output += pad("Study Instance UID", 20) + " " + pad("Patient's Name", 30) + " " + pad("Study Date", 10) + " " + pad("Modalities in Study", 20) + " " + pad("Number of Study Related Series", 30) + "\n"
        output += String(repeating: "=", count: 120) + "\n"
        for study in studies {
            let studyUID = truncate(study.studyInstanceUID ?? "", maxLength: 20)
            let patientName = truncate(study.patientName ?? "", maxLength: 30)
            let studyDate = study.studyDate ?? ""
            let modality = truncate(study.modalitiesInStudy.joined(separator: ", "), maxLength: 20)
            let numSeries = study.numberOfStudyRelatedSeries ?? 0
            output += pad(studyUID, 20) + " " + pad(patientName, 30) + " " + pad(studyDate, 10) + " " + pad(modality, 20) + " " + pad("\(numSeries)", 30) + "\n"
        }
        output += String(repeating: "=", count: 120) + "\n"
        return output
    }

    private func studyDict(_ study: QIDOStudyResult) -> [String: Any] {
        var dict: [String: Any] = [:]
        if let v = study.studyInstanceUID { dict["StudyInstanceUID"] = v }
        if let v = study.patientName { dict["PatientName"] = v }
        if let v = study.patientID { dict["PatientID"] = v }
        if let v = study.studyDate { dict["StudyDate"] = v }
        if let v = study.studyTime { dict["StudyTime"] = v }
        if let v = study.studyDescription { dict["StudyDescription"] = v }
        if let v = study.accessionNumber { dict["AccessionNumber"] = v }
        if let v = study.studyID { dict["StudyID"] = v }
        if let v = study.referringPhysicianName { dict["ReferringPhysicianName"] = v }
        if let v = study.numberOfStudyRelatedSeries { dict["NumberOfStudyRelatedSeries"] = v }
        if let v = study.numberOfStudyRelatedInstances { dict["NumberOfStudyRelatedInstances"] = v }
        if !study.modalitiesInStudy.isEmpty { dict["ModalitiesInStudy"] = study.modalitiesInStudy }
        if let v = study.patientBirthDate { dict["PatientBirthDate"] = v }
        if let v = study.patientSex { dict["PatientSex"] = v }
        return dict
    }

    private func studyCSV(_ studies: [QIDOStudyResult]) -> String {
        var output = "StudyInstanceUID,PatientName,PatientID,StudyDate,StudyDescription,ModalitiesInStudy,NumberOfSeries\n"
        for study in studies {
            let studyUID = csvEscape(study.studyInstanceUID ?? "")
            let patientName = csvEscape(study.patientName ?? "")
            let patientID = csvEscape(study.patientID ?? "")
            let studyDate = study.studyDate ?? ""
            let description = csvEscape(study.studyDescription ?? "")
            let modalities = csvEscape(study.modalitiesInStudy.joined(separator: ";"))
            let numSeries = study.numberOfStudyRelatedSeries ?? 0
            output += "\(studyUID),\(patientName),\(patientID),\(studyDate),\(description),\(modalities),\(numSeries)\n"
        }
        return output
    }

    // MARK: - Series

    public func formatSeries(_ series: [QIDOSeriesResult], format: QIDOOutputFormat) -> String {
        switch format {
        case .table: return seriesTable(series)
        case .json:  return formatJSON(series.map(seriesDict))
        case .csv:   return seriesCSV(series)
        case .dicomJSON: return DICOMJSONModelFormatter.format(series.map(\.attributes))
        }
    }

    private func seriesTable(_ series: [QIDOSeriesResult]) -> String {
        var output = ""
        output += String(repeating: "=", count: 100) + "\n"
        // Column labels are the PS3.6 2026a Table 6-1 Attribute Names (D105).
        output += pad("Series Instance UID", 25) + " " + pad("Modality", 10) + " " + pad("Series Description", 28) + " " + pad("Number of Series Related Instances", 34) + "\n"
        output += String(repeating: "=", count: 100) + "\n"
        for s in series {
            let seriesUID = truncate(s.seriesInstanceUID ?? "", maxLength: 25)
            let modality = s.modality ?? ""
            let description = truncate(s.seriesDescription ?? "", maxLength: 28)
            let numInstances = s.numberOfSeriesRelatedInstances ?? 0
            output += pad(seriesUID, 25) + " " + pad(modality, 10) + " " + pad(description, 28) + " " + pad("\(numInstances)", 34) + "\n"
        }
        output += String(repeating: "=", count: 100) + "\n"
        return output
    }

    private func seriesDict(_ s: QIDOSeriesResult) -> [String: Any] {
        var dict: [String: Any] = [:]
        if let v = s.seriesInstanceUID { dict["SeriesInstanceUID"] = v }
        if let v = s.studyInstanceUID { dict["StudyInstanceUID"] = v }
        if let v = s.modality { dict["Modality"] = v }
        if let v = s.seriesNumber { dict["SeriesNumber"] = v }
        if let v = s.seriesDescription { dict["SeriesDescription"] = v }
        if let v = s.bodyPartExamined { dict["BodyPartExamined"] = v }
        if let v = s.performedProcedureStepStartDate { dict["PerformedProcedureStepStartDate"] = v }
        if let v = s.numberOfSeriesRelatedInstances { dict["NumberOfSeriesRelatedInstances"] = v }
        return dict
    }

    private func seriesCSV(_ series: [QIDOSeriesResult]) -> String {
        var output = "SeriesInstanceUID,StudyInstanceUID,Modality,SeriesNumber,SeriesDescription,NumberOfInstances\n"
        for s in series {
            let seriesUID = csvEscape(s.seriesInstanceUID ?? "")
            let studyUID = csvEscape(s.studyInstanceUID ?? "")
            let modality = s.modality ?? ""
            let seriesNumber = s.seriesNumber ?? 0
            let description = csvEscape(s.seriesDescription ?? "")
            let numInstances = s.numberOfSeriesRelatedInstances ?? 0
            output += "\(seriesUID),\(studyUID),\(modality),\(seriesNumber),\(description),\(numInstances)\n"
        }
        return output
    }

    // MARK: - Instance

    public func formatInstances(_ instances: [QIDOInstanceResult], format: QIDOOutputFormat) -> String {
        switch format {
        case .table: return instanceTable(instances)
        case .json:  return formatJSON(instances.map(instanceDict))
        case .csv:   return instanceCSV(instances)
        case .dicomJSON: return DICOMJSONModelFormatter.format(instances.map(\.attributes))
        }
    }

    private func instanceTable(_ instances: [QIDOInstanceResult]) -> String {
        var output = ""
        output += String(repeating: "=", count: 80) + "\n"
        // Column labels are the PS3.6 2026a Table 6-1 Attribute Names (D105). The SOP
        // Class UID is printed whole (up to 64 characters, PS3.5 VR UI), not truncated.
        output += pad("SOP Instance UID", 30) + " " + pad("SOP Class UID", 30) + " " + pad("Number of Frames", 16) + "\n"
        output += String(repeating: "=", count: 80) + "\n"
        for instance in instances {
            let sopUID = truncate(instance.sopInstanceUID ?? "", maxLength: 30)
            let sopClass = instance.sopClassUID ?? ""
            let numFrames = instance.numberOfFrames ?? 1
            output += pad(sopUID, 30) + " " + pad(sopClass, 30) + " " + pad("\(numFrames)", 16) + "\n"
        }
        output += String(repeating: "=", count: 80) + "\n"
        return output
    }

    private func instanceDict(_ instance: QIDOInstanceResult) -> [String: Any] {
        var dict: [String: Any] = [:]
        if let v = instance.sopInstanceUID { dict["SOPInstanceUID"] = v }
        if let v = instance.sopClassUID { dict["SOPClassUID"] = v }
        if let v = instance.instanceNumber { dict["InstanceNumber"] = v }
        if let v = instance.numberOfFrames { dict["NumberOfFrames"] = v }
        if let v = instance.rows { dict["Rows"] = v }
        if let v = instance.columns { dict["Columns"] = v }
        if let v = instance.seriesInstanceUID { dict["SeriesInstanceUID"] = v }
        if let v = instance.studyInstanceUID { dict["StudyInstanceUID"] = v }
        return dict
    }

    private func instanceCSV(_ instances: [QIDOInstanceResult]) -> String {
        var output = "SOPInstanceUID,SeriesInstanceUID,SOPClassUID,InstanceNumber,NumberOfFrames\n"
        for instance in instances {
            let sopUID = csvEscape(instance.sopInstanceUID ?? "")
            let seriesUID = csvEscape(instance.seriesInstanceUID ?? "")
            let sopClass = csvEscape(instance.sopClassUID ?? "")
            let instanceNumber = instance.instanceNumber ?? 0
            let numFrames = instance.numberOfFrames ?? 1
            output += "\(sopUID),\(seriesUID),\(sopClass),\(instanceNumber),\(numFrames)\n"
        }
        return output
    }

    // MARK: - Utilities

    private func formatJSON(_ data: [[String: Any]]) -> String {
        guard let jsonData = try? JSONSerialization.data(withJSONObject: data, options: [.prettyPrinted, .sortedKeys]),
              let jsonString = String(data: jsonData, encoding: .utf8) else {
            return "[]"
        }
        return jsonString
    }

    private func truncate(_ string: String, maxLength: Int) -> String {
        if string.count <= maxLength { return string }
        let endIndex = string.index(string.startIndex, offsetBy: maxLength - 3)
        return String(string[..<endIndex]) + "..."
    }

    private func pad(_ string: String, _ width: Int) -> String {
        if string.count >= width { return string }
        return string + String(repeating: " ", count: width - string.count)
    }

    private func csvEscape(_ string: String) -> String {
        if string.contains(",") || string.contains("\"") || string.contains("\n") {
            return "\"\(string.replacingOccurrences(of: "\"", with: "\"\""))\""
        }
        return string
    }
}
