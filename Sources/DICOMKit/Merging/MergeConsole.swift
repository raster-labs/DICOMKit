// NEMA-verified: 2026a, checked 2026-09-30 — carries no DICOM-standard data (console output; the MONOCHROME1/MONOCHROME2 terms it prints come from the conversion in Monochrome1Conversion.swift)
import Foundation

/// Console lines and validation messages for `dicom-merge` — the single source of
/// truth used by BOTH the CLI and DICOMStudio's Workshop executor, so their
/// output cannot drift.
///
/// `FrameMerger` already shares the merge itself (and its progress lines through
/// the `log` sink) plus `gatherInputFiles`; the banner, the "Found N files" line,
/// the completion line and the three validation messages were duplicated, and had
/// drifted in three ways: the app dropped the version from the banner, relabelled
/// `Inputs: N path(s)` to `Input: <path>` and padded the `Level:`/`Sort:` labels,
/// and the CLI interpolated the option *enums* (printing `enhancedCt`,
/// `instanceNumber`) where the app printed what the user actually typed
/// (`enhanced-ct`, `InstanceNumber`). The raw values win here.
public enum MergeConsole {
    /// Mirrors `CommandConfiguration.version` in the CLI; part of the banner text.
    public static let toolVersion = "1.1.2"

    // MARK: - Validation messages

    /// No `<inputs>` given at all.
    public static let noInputFilesMessage = "No input files specified"

    /// One of the `<inputs>` roots doesn't exist.
    public static func inputNotFoundMessage(path: String) -> String {
        "Input path does not exist: \(path)"
    }

    /// The roots exist but the (shared, sorted) gather found no DICOM files.
    public static let noDICOMFilesFoundMessage = "No DICOM files found in input paths"

    // MARK: - Console lines

    /// Verbose banner, emitted before gathering. Newline-free lines.
    /// Enhanced-multiframe options are echoed only when they differ from the
    /// defaults so the classic banner is unchanged.
    public static func headerLines(
        inputCount: Int,
        output: String,
        format: MergeFormat,
        level: MergeLevel,
        sortBy: MergeSortCriteria,
        order: MergeSortOrder,
        options: MergeOptions = MergeOptions()
    ) -> [String] {
        var lines = [
            "DICOM Merge Tool v\(toolVersion)",
            "========================",
            "Inputs: \(inputCount) path(s)",
            "Output: \(output)",
            "Format: \(format.rawValue)",
            "Level: \(level.rawValue)",
            "Sort: \(sortBy.rawValue) (\(order.rawValue))",
        ]
        let defaults = MergeOptions()
        if options.pixelHandling != defaults.pixelHandling { lines.append("Pixel handling: \(options.pixelHandling.rawValue)") }
        if options.makeStacks { lines.append("Stacks: by orientation") }
        if options.temporalPositions { lines.append("Temporal positions: yes") }
        if options.newSeries { lines.append("New series: yes") }
        if options.allowAnySource { lines.append("Source gate: disabled") }
        lines.append("")
        return lines
    }

    /// `--format standard` on a classic single-frame IOD: the result is not a
    /// conformant multi-frame object. Always emitted.
    public static func nonMultiframeSOPClassWarning(name: String) -> String {
        "Warning: \(name) is not a multi-frame IOD; use --format auto or an enhanced-*/legacy-converted-* format"
    }

    /// Verbose summary of the functional groups an Enhanced target received.
    public static func functionalGroupLines(
        target: String,
        shared: Int,
        perFrame: Int,
        stacks: Int,
        temporalPositions: Int?,
        dimensionOrganizationType: String?
    ) -> [String] {
        var lines = [
            "Target: \(target)",
            "Functional groups: \(shared) shared, \(perFrame) per-frame",
            "Stacks: \(stacks)",
        ]
        if let temporalPositions { lines.append("Temporal positions: \(temporalPositions)") }
        lines.append("Dimension organization: \(dimensionOrganizationType ?? "none")")
        return lines
    }

    /// A standard merge whose Per-frame items could not be gathered for every frame.
    public static func perFrameFunctionalGroupsDroppedWarning(found: Int, expected: Int) -> String {
        "Warning: dropped Per-frame Functional Groups Sequence (\(found) item(s) for \(expected) frame(s))"
    }

    /// Inputs that are overlapping parts of one concatenation source.
    public static func overlappingConcatenationPartsWarning(source: String) -> String {
        "Warning: inputs cover overlapping frame ranges of concatenation source \(source); frames may be duplicated"
    }

    /// Attributes that vary between frames and had nowhere to go (non-legacy target).
    public static func droppedAttributesWarning(tags: [String]) -> String {
        "Warning: dropped \(tags.count) varying attribute(s) without a functional group: \(tags.joined(separator: ", "))"
    }

    /// Verbose line when the inputs were concatenation parts and were reassembled.
    public static func concatenationReassembledLine(parts: Int, frames: Int, sopInstanceUID: String) -> String {
        "Reassembled concatenation: \(parts) part(s), \(frames) frame(s) -> \(sopInstanceUID)"
    }

    /// Verbose line when MONOCHROME1 frames were inverted to MONOCHROME2 for a target
    /// that allows only MONOCHROME2.
    public static func monochrome1ConvertedLine(frames: Int) -> String {
        "Converted \(frames) MONOCHROME1 frame(s) to MONOCHROME2 (pixel values and window inverted)"
    }

    /// Verbose line for the legacy multi-frame targets (US / SC multi-frame).
    public static func legacyMultiframeLine(target: String, frameTime: String?) -> String {
        if let frameTime, !frameTime.isEmpty {
            return "Target: \(target) (Frame Time \(frameTime.trimmingCharacters(in: .whitespaces)) ms)"
        }
        return "Target: \(target)"
    }

    /// Verbose line emitted once the input files have been gathered.
    public static func foundFilesLines(count: Int) -> [String] {
        ["Found \(count) DICOM files to process", ""]
    }

    /// Final summary (a blank line, then the completion text).
    public static func completionLines() -> [String] {
        ["", "Merge complete!"]
    }
}
