// NEMA-verified: 2026a, checked 2026-09-29 — carries no DICOM-standard data (console output)
import Foundation

/// Console lines and `--variables` parsing for `dicom-script` — the single source
/// of truth used by BOTH the CLI and DICOMStudio's Workshop executor.
///
/// `ScriptExecutor` / `ScriptValidator` / `TemplateGenerator` are already shared
/// (progress flows through the injected `log` sink); what was duplicated was the
/// `validate` verdict block, the `KEY=VALUE` parser and the message the injected
/// command runner throws when it cannot spawn a subprocess — the last of which had
/// drifted ("not supported on this platform" vs "not supported in-app").
public enum ScriptConsole {
    // MARK: - Input parsing

    /// Parses `--variables KEY=VALUE …`. Rejects entries without `=`, matching the
    /// CLI (`ScriptError.invalidVariable`) rather than dropping them silently.
    public static func parseVariables(_ pairs: [String]) throws -> [String: String] {
        var result: [String: String] = [:]
        for pair in pairs {
            let parts = pair.split(separator: "=", maxSplits: 1)
            guard parts.count == 2 else {
                throw ScriptError.invalidVariable(pair)
            }
            result[String(parts[0])] = String(parts[1])
        }
        return result
    }

    // MARK: - Console lines

    /// The `validate` verdict block: one line when clean, otherwise a count line
    /// followed by one indented line per issue.
    public static func validationLines(issues: [String]) -> [String] {
        guard !issues.isEmpty else { return ["\u{2713} Script is valid"] }
        return ["\u{2717} Script has \(issues.count) issue(s):"] + issues.map { "  - \($0)" }
    }

    /// Message for a command runner that cannot spawn subprocesses — the non-macOS/
    /// Linux CLI build and the sandboxed app both throw this, so a script that
    /// shells out reads the same on both surfaces.
    public static func unsupportedRunnerMessage(tool: String) -> String {
        "Command execution is not supported on this platform: \(tool)"
    }
}
