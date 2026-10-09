// NEMA-verified: 2026a, checked 2026-10-01 — binary VRs are the Other VRs of PS3.5 2026a Table 6.2-1 plus UN (D5); Private Creator (gggg,0010-00FF) named per PS3.5 7.8.1 (D146)
import Foundation
import DICOMCore
import DICOMDictionary

/// Output format for a ``ComparisonReport``.
///
/// Lives in the library (not the CLI) so DICOMStudio and the `dicom-diff` tool
/// render reports from the same type. The CLI adds the `ExpressibleByArgument`
/// conformance in its own module.
public enum ComparisonOutputFormat: String, Sendable {
    case text
    case json
    case summary
}

/// Renders a ``ComparisonResult`` as text, JSON, or a short summary.
///
/// Shared by the `dicom-diff` CLI and DICOMStudio so their output cannot drift.
public struct ComparisonReport {
    public let result: ComparisonResult
    public let file1Name: String
    public let file2Name: String
    public let showIdentical: Bool

    public init(result: ComparisonResult, file1Name: String, file2Name: String, showIdentical: Bool) {
        self.result = result
        self.file1Name = file1Name
        self.file2Name = file2Name
        self.showIdentical = showIdentical
    }

    public func render(format: ComparisonOutputFormat) throws -> String {
        switch format {
        case .text:
            return formatTextOutput()
        case .json:
            return try formatJSONOutput()
        case .summary:
            return formatSummaryOutput()
        }
    }

    private func formatTextOutput() -> String {
        var output = ""

        // Summary
        output += "=== DICOM Comparison Results ===\n\n"
        output += "Total tags compared: \(result.totalTags)\n"
        output += "Differences found: \(result.differenceCount)\n"
        output += "Tags only in file 1: \(result.onlyInFile1.count)\n"
        output += "Tags only in file 2: \(result.onlyInFile2.count)\n"
        output += "Modified tags: \(result.modified.count)\n"

        if result.pixelsCompared {
            output += "\nPixel Data: \(result.pixelsDifferent ? "DIFFERENT" : "IDENTICAL")\n"
            if let diff = result.pixelDifference {
                output += "  Max difference: \(diff.maxDifference)\n"
                output += "  Mean difference: \(String(format: "%.2f", diff.meanDifference))\n"
                output += "  Different pixels: \(diff.differentPixelCount) / \(diff.totalPixels)\n"
            }
        }

        output += "\n"

        // Detailed differences
        if !result.onlyInFile1.isEmpty {
            output += "\n--- Tags only in \(file1Name) ---\n"
            for tag in result.onlyInFile1.sorted(by: { $0.key < $1.key }) {
                output += formatTagValue(tag.key, tag.value)
            }
        }

        if !result.onlyInFile2.isEmpty {
            output += "\n--- Tags only in \(file2Name) ---\n"
            for tag in result.onlyInFile2.sorted(by: { $0.key < $1.key }) {
                output += formatTagValue(tag.key, tag.value)
            }
        }

        if !result.modified.isEmpty {
            output += "\n--- Modified Tags ---\n"
            for modification in result.modified.sorted(by: { $0.tag < $1.tag }) {
                let tagName = AttributeNames.name(for: modification.tag) ?? "Unknown"
                output += "\n[\(modification.tag)] \(tagName)\n"
                output += "  File 1: \(formatValue(modification.value1))\n"
                output += "  File 2: \(formatValue(modification.value2))\n"
            }
        }

        if showIdentical && !result.identical.isEmpty {
            output += "\n--- Identical Tags (\(result.identical.count)) ---\n"
            for tag in result.identical.sorted() {
                if let elem = result.file1Data[tag] {
                    output += formatTagValue(tag, elem)
                }
            }
        }

        output += "\n=== End of Comparison ===\n"

        return output
    }

    private func formatJSONOutput() throws -> String {
        var json: [String: Any] = [
            "files": [
                "file1": file1Name,
                "file2": file2Name
            ],
            "summary": [
                "totalTags": result.totalTags,
                "differences": result.differenceCount,
                "hasDifferences": result.hasDifferences
            ],
            // Sort by tag for deterministic output (onlyInFile*/modified are built
            // from unordered collections).
            "onlyInFile1": result.onlyInFile1.sorted { $0.key < $1.key }.map { ["tag": $0.key.description, "value": formatValue($0.value)] },
            "onlyInFile2": result.onlyInFile2.sorted { $0.key < $1.key }.map { ["tag": $0.key.description, "value": formatValue($0.value)] },
            "modified": result.modified.sorted { $0.tag < $1.tag }.map { [
                "tag": $0.tag.description,
                "tagName": AttributeNames.name(for: $0.tag) ?? "Unknown",
                "value1": formatValue($0.value1),
                "value2": formatValue($0.value2)
            ]}
        ]

        if result.pixelsCompared {
            json["pixelData"] = [
                "compared": true,
                "different": result.pixelsDifferent,
                "maxDifference": result.pixelDifference?.maxDifference as Any,
                "meanDifference": result.pixelDifference?.meanDifference as Any,
                "differentPixelCount": result.pixelDifference?.differentPixelCount as Any,
                "totalPixels": result.pixelDifference?.totalPixels as Any
            ] as [String : Any]
        }

        let jsonData = try JSONSerialization.data(withJSONObject: json, options: .prettyPrinted)
        return String(data: jsonData, encoding: .utf8) ?? ""
    }

    private func formatSummaryOutput() -> String {
        var output = ""
        output += "Files: \(result.hasDifferences ? "DIFFERENT" : "IDENTICAL")\n"
        output += "Differences: \(result.differenceCount)\n"
        output += "  Only in file 1: \(result.onlyInFile1.count)\n"
        output += "  Only in file 2: \(result.onlyInFile2.count)\n"
        output += "  Modified: \(result.modified.count)\n"

        if result.pixelsCompared {
            output += "Pixel data: \(result.pixelsDifferent ? "DIFFERENT" : "IDENTICAL")\n"
        }

        return output
    }

    private func formatTagValue(_ tag: Tag, _ element: DataElement) -> String {
        let tagName = AttributeNames.name(for: tag) ?? "Unknown"
        let value = formatValue(element)
        return "[\(tag)] \(tagName): \(value)\n"
    }

    private func formatValue(_ element: DataElement) -> String {
        // Handle different value representations
        if element.vr == .SQ {
            return "<Sequence with \(element.sequenceItems?.count ?? 0) items>"
        }

        // The "Other" byte-stream VRs of PS3.5 Table 6.2-1, plus UN
        if [.OB, .OD, .OF, .OL, .OV, .OW, .UN].contains(element.vr) {
            let byteCount = element.valueData.count
            return "<Binary data, \(byteCount) bytes>"
        }

        return element.stringValue ?? "<empty>"
    }
}
