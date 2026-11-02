import Foundation

/// An example command preset for a tool
public struct ExamplePreset: Identifiable, Sendable {
    public let id: String
    /// Display name for the example
    public let name: String
    /// Description of what this example demonstrates
    public let description: String
    /// Parameter values for this preset
    public let parameterValues: [String: String]
    /// Subcommand (if applicable)
    public let subcommand: String?

    public init(
        id: String? = nil,
        name: String,
        description: String,
        parameterValues: [String: String],
        subcommand: String? = nil
    ) {
        self.id = id ?? name.lowercased().replacingOccurrences(of: " ", with: "-")
        self.name = name
        self.description = description
        self.parameterValues = parameterValues
        self.subcommand = subcommand
    }
}

/// Provides example command presets for each tool
public enum ExamplePresets {
    /// Returns example presets for a given tool ID
    public static func presets(for toolID: String) -> [ExamplePreset] {
        switch toolID {
        case "dicom-info":
            return [
                ExamplePreset(
                    name: "Basic metadata",
                    description: "Display all metadata for a DICOM file in text format",
                    parameterValues: ["filePath": "scan.dcm"]
                ),
                ExamplePreset(
                    name: "JSON output with stats",
                    description: "Output metadata as JSON with file statistics",
                    parameterValues: ["filePath": "scan.dcm", "format": "json", "statistics": "true"]
                ),
                ExamplePreset(
                    name: "Specific tag lookup",
                    description: "Show only specific tags including private tags",
                    parameterValues: ["filePath": "scan.dcm", "tag": "(0010,0010),(0010,0020)", "show-private": "true"]
                ),
            ]
        case "dicom-dump":
            return [
                ExamplePreset(
                    name: "Full hex dump",
                    description: "Hex dump of entire DICOM file with annotations",
                    parameterValues: ["filePath": "scan.dcm", "annotate": "true"]
                ),
                ExamplePreset(
                    name: "Pixel data region",
                    description: "Dump hex around pixel data tag",
                    parameterValues: ["filePath": "scan.dcm", "tag": "(7FE0,0010)", "length": "256"]
                ),
            ]
        case "dicom-tags":
            return [
                ExamplePreset(
                    name: "View all tags",
                    description: "List all tags in a DICOM file",
                    parameterValues: ["input": "scan.dcm"]
                ),
                ExamplePreset(
                    name: "Modify patient name",
                    description: "Change patient name with dry-run preview",
                    parameterValues: ["input": "scan.dcm", "set": "(0010,0010)=ANONYMOUS", "dry-run": "true"]
                ),
            ]
        case "dicom-diff":
            return [
                ExamplePreset(
                    name: "Compare two files",
                    description: "Compare metadata differences between two DICOM files",
                    parameterValues: ["file1": "original.dcm", "file2": "modified.dcm"]
                ),
                ExamplePreset(
                    name: "Compare ignoring private tags",
                    description: "Compare files while ignoring vendor-specific private tags",
                    parameterValues: ["file1": "scan_a.dcm", "file2": "scan_b.dcm", "ignore-private": "true", "format": "json"]
                ),
            ]
        case "dicom-convert":
            return [
                ExamplePreset(
                    name: "Convert to JPEG 2000",
                    description: "Compress a DICOM file using JPEG 2000 lossless",
                    parameterValues: ["inputPath": "input.dcm", "output": "output.dcm", "transfer-syntax": "jpeg2000-lossless"]
                ),
                ExamplePreset(
                    name: "Export as PNG",
                    description: "Export DICOM image to PNG format",
                    parameterValues: ["inputPath": "scan.dcm", "format": "png", "output": "output.png"]
                ),
            ]
        case "dicom-validate":
            return [
                ExamplePreset(
                    name: "Basic validation",
                    description: "Validate DICOM conformance at standard level",
                    parameterValues: ["inputPath": "scan.dcm", "level": "standard"]
                ),
                ExamplePreset(
                    name: "Strict validation with details",
                    description: "Perform strict validation with detailed output in JSON",
                    parameterValues: ["inputPath": "scan.dcm", "level": "strict", "detailed": "true", "format": "json"]
                ),
            ]
        case "dicom-anon":
            return [
                ExamplePreset(
                    name: "PS3.15 anonymization",
                    description: "Apply the PS3.15 workflow; review the output before release",
                    parameterValues: ["inputPath": "scan.dcm", "output": "anon.dcm", "profile": "ps315"]
                ),
                ExamplePreset(
                    name: "Dry-run preview",
                    description: "Preview anonymization changes without modifying files",
                    parameterValues: ["inputPath": "scan.dcm", "profile": "ps315", "dry-run": "true"]
                ),
            ]
        case "dicom-echo":
            return [
                ExamplePreset(
                    name: "Test PACS connectivity",
                    description: "Send C-ECHO to verify PACS connection",
                    parameterValues: [:]
                ),
            ]
        case "dicom-query":
            return [
                ExamplePreset(
                    name: "Find all studies for patient",
                    description: "Query PACS for all studies matching a patient name",
                    parameterValues: ["level": "study", "patient-name": "DOE^JOHN"]
                ),
                ExamplePreset(
                    name: "Find today's CT scans",
                    description: "Query for CT modality studies from today",
                    parameterValues: ["level": "study", "modality": "CT", "study-date": "today"]
                ),
            ]
        case "dicom-report":
            return [
                ExamplePreset(
                    name: "Plain text report",
                    description: "Generate a plain text report from an SR file",
                    parameterValues: ["filePath": "sr.dcm", "output": "report.txt", "format": "text"]
                ),
                ExamplePreset(
                    name: "HTML cardiology report",
                    description: "Generate a styled HTML report using the cardiology template",
                    parameterValues: ["filePath": "sr.dcm", "output": "report.html", "format": "html", "template": "cardiology"]
                ),
                ExamplePreset(
                    name: "Branded radiology report",
                    description: "HTML radiology report with custom title, logo, and footer",
                    parameterValues: ["filePath": "sr.dcm", "output": "report.html", "format": "html", "template": "radiology", "title": "Imaging Report", "logo": "logo.png", "footer": "Confidential Medical Report"]
                ),
                ExamplePreset(
                    name: "JSON data export",
                    description: "Export SR content as structured JSON for integration",
                    parameterValues: ["filePath": "sr.dcm", "output": "data.json", "format": "json"]
                ),
                ExamplePreset(
                    name: "Spanish oncology report",
                    description: "Generate a Markdown oncology report in Spanish",
                    parameterValues: ["filePath": "sr.dcm", "output": "informe.md", "format": "markdown", "template": "oncology", "language": "es"]
                ),
            ]
        default:
            return []
        }
    }
}
