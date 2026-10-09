// NEMA-verified: 2026a, checked 2026-09-29 — carries no DICOM-standard data (console output)
import Foundation
import DICOMCore

/// Console lines for `dicom-convert` — the single source of truth used by BOTH
/// the CLI and DICOMStudio's Workshop executor, so their output cannot drift.
///
/// The CLI's console is deliberately terse: a transcode prints one line (and
/// only when bytes were actually transcoded), an image export prints nothing,
/// and a batch prints one ✓/✗ line per file plus a final summary. An earlier
/// app copy layered extra "Read/Wrote/Transfer Syntax" chrome on top, which
/// made terminal-compare diff on every run.
public enum ConvertConsole {
    /// Single-file transcode result line — emitted only when a transcode
    /// actually happened (same-syntax copies stay silent, like the CLI).
    public static func transcodeLine(
        wasTranscoded: Bool, sourceUID: String, targetUID: String, isLossless: Bool
    ) -> String {
        guard wasTranscoded else { return "" }
        let lossInfo = isLossless ? "lossless" : "lossy"
        return "Transcoded from \(sourceUID) to \(targetUID) (\(lossInfo))\n"
    }

    /// Per-file progress line for a batch (recursive) conversion.
    public static func batchProgressLine(success: Bool, relativePath: String, error: String?) -> String {
        success ? "✓ \(relativePath)\n"
                : "✗ \(relativePath): \(error ?? "unknown error")\n"
    }

    /// Full failure report for a single-file conversion — the text BOTH the CLI and the
    /// app print when a conversion fails, so the two cannot drift. Any error is accepted
    /// and explained through ``ConversionFailure/init(describing:)``.
    public static func failureReport(for error: Error) -> String {
        "❌ Conversion failed\n\(ConversionFailure(describing: error).message)\n"
    }

    /// One-line failure text for a batch progress line (``batchProgressLine(success:relativePath:error:)``).
    public static func failureSummary(for error: Error) -> String {
        ConversionFailure(describing: error).summary
    }

    /// Final batch summary line.
    public static func batchSummary(succeeded: Int, total: Int, failed: Int) -> String {
        "\nConversion complete: \(succeeded)/\(total) succeeded, \(failed) failed\n"
    }

    /// File extension for a `--format` token — the single source of truth for BOTH
    /// the CLI's `OutputFormat.fileExtension` and the app's Workshop executor, which
    /// each previously carried their own copy of this switch. Keeping one map here is
    /// what stops a change like `jpeg → "jpg"` from landing on one surface only.
    ///
    /// Unknown/absent tokens resolve to `dcm`, matching `--format`'s `dicom` default.
    public static func fileExtension(forFormat format: String?) -> String {
        switch format?.lowercased() {
        case "png":  return "png"
        case "jpeg": return "jpg"
        case "tiff": return "tiff"
        default:     return "dcm"
        }
    }
}
