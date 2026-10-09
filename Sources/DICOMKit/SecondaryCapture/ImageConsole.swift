// NEMA-verified: 2026a, checked 2026-09-29 — carries no DICOM-standard data (console output)
import Foundation

/// Builds every console line `dicom-image` prints. The CLI text is canonical and
/// the Workshop executor renders identical strings, so the two surfaces cannot drift.
public enum ImageConsole {
    // MARK: - Directory batch

    /// Verbose batch header (two lines + separating blank line).
    public static func batchHeader(inputPath: String, outputDir: String) -> String {
        "Converting images from: \(inputPath)\nOutput directory: \(outputDir)\n\n"
    }

    /// Verbose per-file line for a non-image file in the directory.
    public static func skippedLine(fileName: String) -> String {
        "⊘ \(fileName): Not a supported image file"
    }

    /// Verbose per-file success line.
    public static func fileSuccessLine(inputName: String, outputName: String) -> String {
        "✓ \(inputName) → \(outputName)"
    }

    /// Verbose per-file failure line.
    public static func fileFailureLine(inputName: String, message: String) -> String {
        "✗ \(inputName): \(message)"
    }

    /// The unconditional end-of-batch summary block (leading blank line).
    /// "Failed" appears only when at least one file failed.
    public static func batchSummary(
        successful: Int, failed: Int,
        studyUID: String, seriesUID: String, outputDir: String
    ) -> String {
        var out = "\nConversion complete:\n"
        out += "  Successful: \(successful)\n"
        if failed > 0 { out += "  Failed: \(failed)\n" }
        out += "  Study UID: \(studyUID)\n"
        out += "  Series UID: \(seriesUID)\n"
        out += "  Output directory: \(outputDir)\n"
        return out
    }

    // MARK: - Single file

    /// Verbose pre-conversion line.
    public static func convertingLine(inputPath: String) -> String {
        "Converting image: \(inputPath)"
    }

    /// Result line — checkmarked in verbose mode, plain otherwise.
    public static func convertedLine(outputPath: String, verbose: Bool) -> String {
        verbose ? "✓ Converted to: \(outputPath)" : "Converted: \(outputPath)"
    }

    // MARK: - Multi-page TIFF split

    /// Verbose TIFF-split header (three lines + separating blank line).
    public static func tiffHeader(fileName: String, pages: Int, outputDir: String) -> String {
        "Splitting multi-page TIFF: \(fileName)\nPages: \(pages)\nOutput directory: \(outputDir)\n\n"
    }

    /// Verbose per-page success line (1-based page number).
    public static func pageSuccessLine(page: Int, outputName: String) -> String {
        "✓ Page \(page) → \(outputName)"
    }

    /// Verbose per-page failure line (1-based page number).
    public static func pageFailureLine(page: Int, message: String) -> String {
        "✗ Page \(page): \(message)"
    }

    /// The unconditional end-of-split summary block (leading blank line).
    public static func tiffSummary(pages: Int, outputDir: String) -> String {
        "\nMulti-page TIFF conversion complete:\n  Pages: \(pages)\n  Output directory: \(outputDir)\n"
    }
}
