// NEMA-verified: 2026a, checked 2026-09-29 — SOP Class names match PS3.6 2026a Table A-1
import Foundation

/// Console lines and input parsing for `dicom-split` — the single source of truth
/// used by BOTH the CLI and DICOMStudio's Workshop executor, so their output
/// cannot drift.
///
/// `FrameSplitter` already shares the per-file progress lines through its `log`
/// sink; what lived in two places was everything around it: the verbose banner,
/// the completion summary, the `--frames` parser and the two input-validation
/// messages. The two copies had already drifted (the app dropped the version
/// from the banner and replaced the stats line with prose), which is exactly
/// what this type exists to prevent.
public enum SplitConsole {
    /// Mirrors `CommandConfiguration.version` in the CLI; part of the banner text.
    public static let toolVersion = "1.1.2"

    // MARK: - Input parsing

    /// A bad `--frames` selection. Carries the CLI-exact message so the CLI can
    /// re-wrap it in `ValidationError` and the app can print it verbatim.
    public struct FrameSelectionError: Error, CustomStringConvertible, LocalizedError {
        public let description: String
        public init(_ description: String) { self.description = description }
        public var errorDescription: String? { description }
    }

    /// Parses a `--frames` selection such as `1,3,5-10` into 0-based frame indices.
    ///
    /// `split(separator:)` omits empty components, so `1,` and `1,,2` are accepted;
    /// a whitespace-only component (`1, ,2`) is not — it fails as "Invalid frame
    /// number:", which is what the CLI always did. The app's copy skipped those
    /// components instead, silently running a different frame set.
    public static func parseFrameSelection(_ spec: String) throws -> Set<Int> {
        var indices = Set<Int>()

        for rawPart in spec.split(separator: ",") {
            let part = rawPart.trimmingCharacters(in: .whitespaces)
            if part.contains("-") {
                // Range like "5-10"
                let bounds = part.split(separator: "-").map { $0.trimmingCharacters(in: .whitespaces) }
                guard bounds.count == 2,
                      let start = Int(bounds[0]),
                      let end = Int(bounds[1]),
                      start <= end else {
                    throw FrameSelectionError("Invalid frame range: \(part)")
                }
                for i in start...end { indices.insert(i) }
            } else {
                guard let index = Int(part) else {
                    throw FrameSelectionError("Invalid frame number: \(part)")
                }
                indices.insert(index)
            }
        }

        return indices
    }

    /// Parses a `--frame-numbers` selection such as `1,3,5-10` — Frame numbers, numbered from 1
    /// (PS3.3 2026a C.7.6.16.1.2 "Frames are implicitly numbered starting from 1"; Table 10-3) —
    /// into 0-based frame indices (P-SPLIT-1). Same grammar as ``parseFrameSelection(_:)``; a
    /// Frame number below 1 is an error.
    public static func parseFrameNumberSelection(_ spec: String) throws -> Set<Int> {
        let numbers = try parseFrameSelection(spec)
        if let bad = numbers.filter({ $0 < 1 }).min() {
            throw FrameSelectionError("Invalid frame number: \(bad) (Frame numbers start at 1, PS3.3 C.7.6.16.1.2)")
        }
        return Set(numbers.map { $0 - 1 })
    }

    /// One-line stderr note when the deprecated 0-based `--frames` is used (P-SPLIT-1). The
    /// Workshop prints it too when its `frames` parameter is used.
    public static let framesDeprecatedLine =
        "warning: --frames is deprecated (0-based index); use --frame-numbers (numbered from 1, PS3.3 C.7.6.16.1.2)"

    /// `--frames` and `--frame-numbers` given together (exit 1).
    public static let framesAndFrameNumbersConflictMessage =
        "--frames (deprecated, 0-based) and --frame-numbers (numbered from 1) cannot be used together"

    // MARK: - Option help + ArgumentParser-shaped value errors

    /// Help text of the numeric options. Single-sourced here because the CLI's
    /// `@Option(help:)` prints it in ArgumentParser's "Help:" line for an
    /// unparseable value, and the Workshop reproduces that line verbatim.
    public static let windowCenterHelp = "Window center for image rendering"
    public static let windowWidthHelp = "Window width for image rendering"
    public static let framesPerHelp = "Write concatenation parts of N frames (SOP class kept; the only legal split for Segmentation / Parametric Map)"

    /// `--frames-per 0` (or negative). The CLI throws this inside `ValidationError`.
    public static let framesPerTooSmallMessage = "--frames-per must be at least 1"

    /// The two lines ArgumentParser prints when an option value cannot be parsed
    /// (`dicom-split --frames-per x`): the error, then the option's help. `option`
    /// is the long flag; the value name is derived from it the way ArgumentParser
    /// does for a long-only option.
    public static func invalidValueLines(value: String, option: String, help: String) -> [String] {
        let valueName = option.hasPrefix("--") ? String(option.dropFirst(2)) : option
        let usage = "\(option) <\(valueName)>"
        return ["Error: The value '\(value)' is invalid for '\(usage)'",
                "Help:  \(usage)  \(help)"]
    }

    // MARK: - Validation messages

    /// Input path missing. The CLI throws this inside `ValidationError` (which
    /// ArgumentParser prints as `Error: <message>`), so the app prefixes it the
    /// same way.
    public static func inputNotFoundMessage(path: String) -> String {
        "Input path does not exist: \(path)"
    }

    /// `--output` names something that already exists and isn't a directory.
    public static func outputNotDirectoryMessage(path: String) -> String {
        "Output path exists but is not a directory: \(path)"
    }

    // MARK: - Console lines

    /// Verbose banner, emitted before any frame work. Newline-free lines.
    /// Enhanced-multiframe options are echoed only when they differ from the
    /// defaults so the classic banner is unchanged.
    public static func headerLines(
        input: String,
        output: String,
        format: SplitOutputFormat,
        frames: String?,
        applyWindow: Bool,
        windowCenter: Double?,
        windowWidth: Double?,
        options: SplitOptions = SplitOptions(),
        frameNumbers: String? = nil
    ) -> [String] {
        var lines = [
            "DICOM Split Tool v\(toolVersion)",
            "========================",
            "Input: \(input)",
            "Output: \(output)",
            "Format: \(format.rawValue)",
        ]
        if let frames, !frames.isEmpty {
            lines.append("Frames: \(frames)")
        }
        if let frameNumbers, !frameNumbers.isEmpty {
            lines.append("Frame numbers: \(frameNumbers)")
        }
        if applyWindow {
            lines.append("Window Center: \(windowCenter ?? 0)")
            lines.append("Window Width: \(windowWidth ?? 0)")
        }
        let defaults = SplitOptions()
        if options.target != defaults.target { lines.append("Target: \(options.target.rawValue)") }
        if options.pixelHandling != defaults.pixelHandling { lines.append("Pixel handling: \(options.pixelHandling.rawValue)") }
        if options.privateGroups != defaults.privateGroups { lines.append("Private groups: \(options.privateGroups.rawValue)") }
        if options.instanceNumbering != defaults.instanceNumbering { lines.append("Instance numbering: \(options.instanceNumbering.rawValue)") }
        if options.seriesGrouping != defaults.seriesGrouping { lines.append("Split by: \(options.seriesGrouping.rawValue)") }
        if options.newSeries { lines.append("New series: yes") }
        if let per = options.framesPerInstance, per > 0 { lines.append("Frames per instance: \(per)") }
        if !options.deterministicUIDs { lines.append("UIDs: random") }
        lines.append("")
        return lines
    }

    /// Verbose per-file plan: what the frames become.
    public static func planLines(
        sourceName: String,
        targetSOPClassUID: String?,
        functionalGroups: Bool,
        seriesCount: Int
    ) -> [String] {
        var lines: [String] = []
        if let target = targetSOPClassUID {
            let targetName = MultiframeSOPClassMap.entry(for: target)?.name ?? classicName(target)
            lines.append("  SOP Class: \(sourceName) -> \(targetName)")
        } else {
            lines.append("  SOP Class: \(sourceName) (kept, one frame per instance)")
        }
        if functionalGroups {
            lines.append(targetSOPClassUID != nil
                         ? "  Functional groups: flattened to top level"
                         : "  Functional groups: per-frame item retained")
        }
        if seriesCount > 1 {
            lines.append("  Output series: \(seriesCount)")
        }
        return lines
    }

    /// A source file that cannot be split (Segmentation, no classic counterpart…).
    public static func skippedLine(path: String, reason: String) -> String {
        "Warning: Skipping \(path): \(reason)"
    }

    /// Verbose line announcing a concatenation split.
    public static func concatenationPlanLine(parts: Int, framesPerInstance: Int) -> String {
        "  Concatenation: \(parts) part(s) of up to \(framesPerInstance) frame(s)"
    }

    /// `--frames` / `--frame-numbers` have no meaning when writing concatenation parts.
    public static let frameSelectionIgnoredForConcatenationLine =
        "Warning: --frames / --frame-numbers is ignored when --frames-per writes concatenation parts"

    static func classicName(_ uid: String) -> String {
        typealias U = MultiframeSOPClassMap.UID
        switch uid {
        case U.ctImage: return "CT Image Storage"
        case U.mrImage: return "MR Image Storage"
        case U.petImage: return "Positron Emission Tomography Image Storage"
        case U.xaImage: return "X-Ray Angiographic Image Storage"
        case U.xrfImage: return "X-Ray Radiofluoroscopic Image Storage"
        case U.usImage: return "Ultrasound Image Storage"
        case U.secondaryCapture: return "Secondary Capture Image Storage"
        default: return uid
        }
    }

    /// Final summary. Always emitted (including the all-zero case), so a run that
    /// found nothing to split still reports its counts instead of prose.
    public static func completionLines(result: SplitResult) -> [String] {
        ["",
         "Split complete! Processed: \(result.processedFiles), extracted: \(result.extracted), "
         + "skipped: \(result.skippedFiles), failed: \(result.failed)"]
    }
}
