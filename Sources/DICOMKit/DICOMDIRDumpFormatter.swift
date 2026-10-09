// NEMA-verified: 2026a, checked 2026-10-01 — non-IMAGE instance records (Table F.4-1) named with their Instance Number and File ID and counted as "Other instance records" (D230); --verbose record keys are labelled "(gggg,eeee) <PS3.6 2026a Table 6-1 / 8-1 Attribute Name>" from DICOMDictionary (D128); the File-set Consistency Flag (0004,1212) is printed under its PS3.6 name with the PS3.3 2026a Table F.3-3 Enumerated Value text (0000H "no known inconsistencies"; FFFFH "shall never be present")
import Foundation
import DICOMCore
import DICOMDictionary

/// Shared renderer for `dicom-dcmdir dump` output.
///
/// The `dicom-dcmdir` CLI and DICOMStudio's CLI Workshop both render DICOMDIR
/// structure through this one formatter, so the tree / json / text output cannot
/// drift between the two surfaces. The formatter returns a `String`: the CLI
/// prints it (with an empty terminator so it does not add a second trailing
/// newline) and the app appends it to its console buffer.
public enum DICOMDIRDumpFormatter {

    /// Output format for a DICOMDIR dump.
    public enum Format: String, CaseIterable, Sendable {
        case tree
        case json
        case text
    }

    /// Renders a DICOMDIR in the requested format.
    ///
    /// Returns `nil` for an unrecognized format string so each caller can report
    /// the error using its own exit-code / console-status convention.
    public static func render(_ directory: DICOMDirectory, format: String, verbose: Bool) -> String? {
        guard let parsed = Format(rawValue: format.lowercased()) else { return nil }
        return render(directory, format: parsed, verbose: verbose)
    }

    /// Renders a DICOMDIR in the requested format.
    public static func render(_ directory: DICOMDirectory, format: Format, verbose: Bool) -> String {
        switch format {
        case .tree: return renderTree(directory, verbose: verbose)
        case .json: return renderJSON(directory)
        case .text: return renderText(directory, verbose: verbose)
        }
    }

    // MARK: - Labels

    /// `(gggg,eeee) <Attribute Name>` with the PS3.6 Attribute Name of the tag, or the bare
    /// tag when the data dictionary does not define it (e.g. a private attribute).
    public static func attributeLabel(_ tag: Tag) -> String {
        guard let name = DataElementDictionary.lookup(tag: tag)?.name, !name.isEmpty else {
            return tag.description
        }
        return "\(tag.description) \(name)"
    }

    /// The File-set Consistency Flag (0004,1212) value with its PS3.3 Table F.3-3 meaning.
    public static func consistencyFlagText(_ isConsistent: Bool) -> String {
        isConsistent
            ? "0000H (no known inconsistencies)"
            : "FFFFH (retired value; PS3.3 Table F.3-3: shall never be present)"
    }

    // MARK: - Tree

    private static func renderTree(_ directory: DICOMDirectory, verbose: Bool) -> String {
        var out = ""
        out += "DICOMDIR: \(directory.fileSetID)\n"
        out += "├─ Profile: \(directory.profile.rawValue)\n"
        out += "├─ File-set Consistency Flag: \(consistencyFlagText(directory.isConsistent))\n"
        out += "└─ Records:\n"
        for (index, patient) in directory.rootRecords.enumerated() {
            let isLast = index == directory.rootRecords.count - 1
            appendRecord(patient, prefix: isLast ? "    " : "│   ", isLast: true, verbose: verbose, into: &out)
        }
        return out
    }

    private static func appendRecord(
        _ record: DirectoryRecord, prefix: String, isLast: Bool, verbose: Bool, into out: inout String
    ) {
        let connector = isLast ? "└── " : "├── "
        out += "\(prefix)\(connector)\(formatRecordName(record))\n"
        if verbose {
            for (tag, element) in record.attributes.sorted(by: { $0.key < $1.key }) {
                if let stringValue = element.stringValue {
                    let attrPrefix = isLast ? "    " : "│   "
                    out += "\(prefix)\(attrPrefix)    \(attributeLabel(tag)): \(stringValue)\n"
                }
            }
        }
        let childPrefix = prefix + (isLast ? "    " : "│   ")
        for (index, child) in record.children.enumerated() {
            let childIsLast = index == record.children.count - 1
            appendRecord(child, prefix: childPrefix, isLast: childIsLast, verbose: verbose, into: &out)
        }
    }

    /// Builds the single-line label for a directory record (record type plus a
    /// few type-specific identifying attributes).
    public static func formatRecordName(_ record: DirectoryRecord) -> String {
        var name = record.recordType.rawValue
        switch record.recordType {
        case .patient:
            if let patientName = record.attribute(for: .patientName)?.stringValue {
                name += " - \(patientName)"
            }
            if let patientID = record.attribute(for: .patientID)?.stringValue {
                name += " (ID: \(patientID))"
            }
        case .study:
            if let studyDesc = record.attribute(for: .studyDescription)?.stringValue {
                name += " - \(studyDesc)"
            }
            if let studyDate = record.attribute(for: .studyDate)?.stringValue {
                name += " [\(studyDate)]"
            }
        case .series:
            if let modality = record.attribute(for: .modality)?.stringValue {
                name += " - \(modality)"
            }
            if let seriesDesc = record.attribute(for: .seriesDescription)?.stringValue {
                name += " - \(seriesDesc)"
            }
        case let type where type == .image || record.referencedSOPInstanceUID != nil:
            // IMAGE and the other instance records (SR DOCUMENT, PRESENTATION, …; Table F.4-1)
            if let instanceNum = record.attribute(for: .instanceNumber)?.stringValue {
                name += " #\(instanceNum)"
            }
            if let filePath = record.referencedFilePath() {
                name += " (\(filePath))"
            }
        default:
            break
        }
        return name
    }

    // MARK: - JSON

    private static func renderJSON(_ directory: DICOMDirectory) -> String {
        let stats = directory.statistics()
        var out = ""
        out += "{\n"
        out += "  \"fileSetID\": \"\(directory.fileSetID)\",\n"
        out += "  \"profile\": \"\(directory.profile.rawValue)\",\n"
        out += "  \"isConsistent\": \(directory.isConsistent),\n"
        out += "  \"statistics\": {\n"
        out += "    \"patients\": \(stats.patientCount),\n"
        out += "    \"studies\": \(stats.studyCount),\n"
        out += "    \"series\": \(stats.seriesCount),\n"
        out += "    \"images\": \(stats.imageCount)\n"
        out += "  },\n"
        out += "  \"recordCount\": \(stats.totalRecordCount)\n"
        out += "}\n"
        return out
    }

    // MARK: - Text

    private static func renderText(_ directory: DICOMDirectory, verbose: Bool) -> String {
        var out = ""
        out += "DICOMDIR Information\n"
        out += "====================\n\n"
        out += "File-set ID: \(directory.fileSetID.isEmpty ? "<none>" : directory.fileSetID)\n"
        out += "Profile: \(directory.profile.rawValue)\n"
        out += "File-set Consistency Flag: \(consistencyFlagText(directory.isConsistent))\n\n"
        let stats = directory.statistics()
        out += "Statistics:\n"
        out += "  Patients: \(stats.patientCount)\n"
        out += "  Studies: \(stats.studyCount)\n"
        out += "  Series: \(stats.seriesCount)\n"
        out += "  Images: \(stats.imageCount)\n"
        if stats.instanceRecordCount > stats.imageCount {
            out += "  Other instance records: \(stats.instanceRecordCount - stats.imageCount)\n"
        }
        out += "  Total records: \(stats.totalRecordCount)\n\n"
        if verbose {
            out += "All Records:\n"
            out += "------------\n"
            for record in directory.allRecords() {
                out += "\n"
                out += "Type: \(record.recordType.rawValue)\n"
                if let filePath = record.referencedFilePath() {
                    out += "File: \(filePath)\n"
                }
                for (tag, element) in record.attributes.sorted(by: { $0.key < $1.key }) {
                    if let value = element.stringValue {
                        out += "  \(attributeLabel(tag)): \(value)\n"
                    }
                }
            }
        }
        return out
    }
}
