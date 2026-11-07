// J2KTestBenchExporter.swift
// DICOMStudio
//
// DICOM Studio — renders a completed J2K Test Bench run as CSV or Markdown.

import Foundation

/// Serializes a ``J2KTestRun`` to shareable text formats.
public enum J2KTestBenchExporter {

    /// CSV — one row per cell, suitable for spreadsheets.
    public static func csv(_ run: J2KTestRun) -> String {
        var lines: [String] = [
            "fixture,transfer_syntax,codec,encode_ms,decode_ms,encoded_bytes,raw_bytes,ratio,psnr_db,outcome,detail"
        ]
        for cell in run.cells {
            let fields: [String] = [
                field(cell.fixtureName),
                field(cell.syntaxName),
                field(cell.codec.displayName),
                number(cell.encodeMs),
                number(cell.decodeMs),
                cell.encodedBytes.map(String.init) ?? "",
                cell.rawBytes.map(String.init) ?? "",
                cell.compressionRatio.map { String(format: "%.3f", $0) } ?? "",
                psnrCSV(cell.psnrDb, outcome: cell.outcome),
                field(outcomeWord(cell.outcome)),
                field(cell.outcome.detail),
            ]
            lines.append(fields.joined(separator: ","))
        }
        return lines.joined(separator: "\n") + "\n"
    }

    /// Markdown — a metadata header plus a results table, formatted to paste
    /// straight into a benchmark document.
    public static func markdown(_ run: J2KTestRun) -> String {
        var out = "# J2K Test Bench — \(timestamp(run.timestamp))\n\n"
        out += "- Environment: \(run.environment)\n"
        out += "- Corpus: \(run.fixtureCount) fixture(s) × \(run.syntaxCount) transfer syntax(es)\n"
        out += "- Result: **\(run.passCount)/\(run.totalCount) passed**"
        if run.failCount > 0 { out += " · \(run.failCount) not passing" }
        out += "\n\n"
        out += "| Fixture | Transfer Syntax | Codec | Encode | Decode | Ratio | PSNR | Outcome |\n"
        out += "|---|---|---|--:|--:|--:|--:|:--|\n"
        for cell in run.cells {
            let columns = [
                cell.fixtureName,
                cell.syntaxName,
                cell.codec.displayName,
                msText(cell.encodeMs),
                msText(cell.decodeMs),
                cell.compressionRatio.map { String(format: "%.2f×", $0) } ?? "—",
                psnrLabel(cell.psnrDb, outcome: cell.outcome),
                outcomeMarkdown(cell.outcome),
            ]
            out += "| " + columns.joined(separator: " | ") + " |\n"
        }
        return out
    }

    // MARK: - Helpers

    private static func field(_ string: String) -> String {
        if string.contains(",") || string.contains("\"") || string.contains("\n") {
            return "\"" + string.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        return string
    }

    private static func number(_ value: Double?) -> String {
        value.map { String(format: "%.3f", $0) } ?? ""
    }

    private static func msText(_ value: Double?) -> String {
        value.map { String(format: "%.2f ms", $0) } ?? "—"
    }

    private static func psnrCSV(_ psnr: Double?, outcome: J2KTestOutcome) -> String {
        if psnr == nil && outcome.isPass { return "inf" }
        return psnr.map { String(format: "%.2f", $0) } ?? ""
    }

    private static func psnrLabel(_ psnr: Double?, outcome: J2KTestOutcome) -> String {
        if psnr == nil && outcome.isPass { return "∞ (bit-exact)" }
        return psnr.map { String(format: "%.1f dB", $0) } ?? "—"
    }

    private static func outcomeWord(_ outcome: J2KTestOutcome) -> String {
        switch outcome {
        case .pass: return "pass"
        case .fail: return "fail"
        case .error: return "error"
        case .skipped: return "skipped"
        }
    }

    private static func outcomeMarkdown(_ outcome: J2KTestOutcome) -> String {
        switch outcome {
        case .pass: return "✅ Pass"
        case .fail(let reason): return "❌ \(reason)"
        case .error(let reason): return "⚠️ \(reason)"
        case .skipped(let reason): return "– \(reason)"
        }
    }

    private static func timestamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter.string(from: date)
    }
}
