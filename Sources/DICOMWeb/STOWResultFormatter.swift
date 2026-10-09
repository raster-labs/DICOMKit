import Foundation

// NEMA-verified: 2026a, checked 2026-10-01 — Failure Reason (0008,1197) and Warning Reason (0008,1196) print as hex (decimal): meaning per PS3.18 2026a Tables I.2-2 (6 rows) / I.2-1 (3 rows), dumped by Scripts/nema_docbook.py (D106)
/// Console renderings shared by the `dicom-wado store` CLI (STOW-RS) and
/// DICOMStudio's in-app STOW upload, so both produce identical text for the same
/// upload outcome. This is the store-side peer of `QIDOResultFormatter` (query) and
/// `UPSResultFormatter` (ups): a SINGLE formatter both sides call, so their output
/// pipelines cannot drift.
///
/// The line/block strings here are the canonical `dicom-wado store` output — the
/// CLI-parity comparator's `parseStore` anchors on the "Upload Summary:" markers, so
/// the summary block format is a contract and must not change without updating that
/// parser (`CLIParityWADOComparator.parseStore`) and its unit test.
///
/// Each method returns text WITHOUT a trailing newline; callers add line termination
/// (the CLI via `fprintln`, the app via `appendConsoleOutput(_ + "\n")`).
public struct STOWResultFormatter {
    public init() {}

    /// The verbose pre-upload header block (emitted only under `--verbose`).
    /// Mirrors the CLI's preamble:
    ///   DICOMweb Server: <baseURL>
    ///   Target Study: <uid>        (only when a target study is set)
    ///   Files to upload: <count>
    ///   Batch size: <batch>
    public func header(baseURL: String, targetStudyUID: String?, fileCount: Int, batchSize: Int) -> String {
        var lines = ["DICOMweb Server: \(baseURL)"]
        if let uid = targetStudyUID, !uid.isEmpty {
            lines.append("Target Study: \(uid)")
        }
        lines.append("Files to upload: \(fileCount)")
        lines.append("Batch size: \(batchSize)")
        return lines.joined(separator: "\n")
    }

    /// Verbose per-batch start line: `Batch <n>: Uploading <count> file(s)...`
    public func batchStart(batchNumber: Int, fileCount: Int) -> String {
        "Batch \(batchNumber): Uploading \(fileCount) file(s)..."
    }

    /// Verbose per-batch result line: `  Success: <s>, Failure: <f>`
    public func batchResult(success: Int, failure: Int) -> String {
        "  Success: \(success), Failure: \(failure)"
    }

    /// Verbose per-failure detail line: `    Failed: <sopInstanceUID> - <reason>`.
    /// `uid` falls back to "unknown" and `reason` should already be resolved
    /// (description, else "Code <n>", else "unknown error").
    public func failureDetail(sopInstanceUID: String?, reason: String) -> String {
        "    Failed: \(sopInstanceUID ?? "unknown") - \(reason)"
    }

    /// Resolves a STOW failure to its human-readable reason, identical on both sides.
    /// A Failure Reason (0008,1197) prints as `<hex> (<decimal>): <meaning>` with the
    /// PS3.18 2026a Table I.2-2 meaning (e.g. `A701 (42753): Refused out of Resources`),
    /// followed by the server's description in brackets when there is one; without a code,
    /// the description, else "unknown error".
    public func failureReason(description: String?, code: UInt16?) -> String {
        guard let code else { return description ?? "unknown error" }
        let text = STOWResponse.describe(code: code,
                                         meaning: STOWResponse.standardMeaning(forFailureReason: code),
                                         table: "I.2-2")
        if let description, !description.isEmpty { return text + " [\(description)]" }
        return text
    }

    /// Verbose per-warning line for an instance stored with a Warning Reason (0008,1196):
    /// `    Warning: <sopInstanceUID> - <hex> (<decimal>): <meaning>` with the PS3.18 2026a
    /// Table I.2-1 meaning, e.g. `B000 (45056): Coercion of Data Elements`.
    public func warningDetail(sopInstanceUID: String, code: UInt16) -> String {
        let text = STOWResponse.describe(code: code,
                                         meaning: STOWResponse.standardMeaning(forWarningReason: code),
                                         table: "I.2-1")
        return "    Warning: \(sopInstanceUID) - \(text)"
    }

    /// The always-printed final summary block (the parity contract):
    ///
    ///     <blank line>
    ///     Upload Summary:
    ///       Total files: <total>
    ///       Successful: <succeeded>
    ///       Failed: <failed>
    public func summary(total: Int, succeeded: Int, failed: Int) -> String {
        """

        Upload Summary:
          Total files: \(total)
          Successful: \(succeeded)
          Failed: \(failed)
        """
    }
}
