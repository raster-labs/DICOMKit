// NEMA-verified: 2026a, checked 2026-10-05 — carries no DICOM-standard data (testing-only: spawns the real dicom-* binary with the Workshop's pasted command and diffs both consoles, ANSI stripped; the output parity it measures is pinned by SplitMergeWorkshopCLIParityTests and NetworkToolWorkshopCLIParityTests; grep for tags, UIDs, STD-* profiles, VR codes and PS3 clauses found none)
// CLIToolTerminalCompare.swift
// DICOMStudio
//
// ╔══════════════════════════════════════════════════════════════════════════╗
// ║  ⚠️  TESTING-ONLY — REMOVE BEFORE PRODUCTION  ⚠️                            ║
// ╚══════════════════════════════════════════════════════════════════════════╝
//
// Spawns the REAL `dicom-*` CLI binary for the currently-selected tool as a
// subprocess, so the CLI Workshop can show the terminal output side-by-side with
// the app's in-process output (a parity sanity check while developing).
//
// It only works when the App Sandbox is DISABLED — a sandboxed app cannot launch
// external executables.
//
// STATUS (2026-08-03): the App Sandbox is ENABLED again in DICOMStudio.entitlements,
// and the Workshop's "Compare CLI (TEST)" button + side-by-side panel have been
// removed. This file and its `runTerminalCompare()` caller in CLIWorkshopViewModel
// are deliberately KEPT for future testing, but they are DORMANT: with the sandbox
// on, `run(...)` will fail to launch and report a launchError. To use it locally,
// temporarily set `com.apple.security.app-sandbox` to <false/>, add a UI entry
// point, and revert both before shipping. See project memory
// `dicom-info-terminal-compare-testonly` and `cli-parity-harness-removed`.

import Foundation

/// Result of a TESTING-ONLY terminal-vs-app output comparison for one tool.
/// Plain data (no platform APIs) so it is available on every platform.
struct CLIToolCompareResult: Sendable, Equatable {
    var toolName: String           // e.g. "dicom-info"
    var appOutput: String          // app's in-process render
    var terminalOutput: String     // real CLI binary stdout (or error text)
    var binaryPath: String?        // which binary was executed
    var commandLine: String        // the command that was run (for display)
    var matched: Bool              // normalized outputs are identical
    var differingLineCount: Int    // # of non-matching lines (normalized)
    var note: String               // human-readable status
}

#if os(macOS)

/// TESTING-ONLY helper that locates and runs a `dicom-*` CLI binary.
enum CLIToolTerminalCompare {

    struct Outcome: Sendable {
        var binaryPath: String?
        var stdout: String
        var stderr: String
        var exitCode: Int32
        var launchError: String?

        /// stdout + stderr as a real terminal shows them — both streams share one
        /// TTY, so the user sees them together. We can't recover the exact byte
        /// interleaving from two separate pipes, so we append stderr after stdout.
        /// That reproduces the terminal's order whenever stderr is written at
        /// END-OF-RUN, which covers every success path here: `dicom-echo` flushes its
        /// progress dots to stdout *during* the run and writes the `Summary:` / stats
        /// block to stderr at the end (likewise `--verbose` / `--diagnose` / `--stats`,
        /// and `dicom-query` / `dicom-send`, which put data on stdout and logs on
        /// stderr). The one approximate case is a FAILED run (e.g. `dicom-echo
        /// --count N` with a failed echo): its per-attempt `✗` lines go to stderr
        /// *mid-loop*, interleaved with the stdout dots, so the concatenated panel
        /// shows a dots-block then an errors-block rather than true interleaving —
        /// faithful ordering there would need a PTY. The compare VERDICT is unaffected
        /// (`normalize` below canonicalizes blank lines / order). Callers that need
        /// the streams apart keep reading `stdout` / `stderr` separately.
        var combined: String {
            if stdout.isEmpty { return stderr }
            if stderr.isEmpty { return stdout }
            return stdout + stderr
        }
    }

    /// Splits a command string (as produced by `CommandBuilderHelpers.buildCommand`,
    /// which single-quote-escapes values) into argv tokens — WITHOUT a shell.
    /// Handles `'…'` quoting and the `'\''` escaped-quote idiom, so a previewed
    /// command is the single source of truth for what gets executed.
    static func shellSplit(_ command: String) -> [String] {
        var args: [String] = []
        var cur = ""
        var hasToken = false
        var inSingle = false
        var idx = command.startIndex
        while idx < command.endIndex {
            let c = command[idx]
            if inSingle {
                if c == "'" { inSingle = false } else { cur.append(c) }
                hasToken = true
            } else {
                switch c {
                case "'":
                    inSingle = true; hasToken = true
                case "\\":
                    let n = command.index(after: idx)
                    if n < command.endIndex { cur.append(command[n]); idx = n; hasToken = true }
                case " ", "\t", "\n":
                    if hasToken { args.append(cur); cur = ""; hasToken = false }
                default:
                    cur.append(c); hasToken = true
                }
            }
            idx = command.index(after: idx)
        }
        if hasToken { args.append(cur) }
        return args
    }

    // MARK: Output normalization
    //
    // Canonicalizes raw tool output into comparable lines so the side-by-side
    // verdict ignores differences that are volatile by construction (wall-clock
    // timestamps, durations, absolute fixture paths, ANSI color, box-drawing vs
    // ASCII rules, JSON key order) rather than semantic. Moved here from the
    // removed CLIParityEngine, which used to own it.

    /// Normalizes raw tool output into comparable lines: strips the Studio's
    /// "$ command" echo and status decoration, canonicalizes the fixture path,
    /// and trims whitespace.
    static func normalize(_ raw: String, fixtureBasename: String) -> [String] {
        normalize(raw, fixtureBasenames: fixtureBasename.isEmpty ? [] : [fixtureBasename])
    }

    /// Multi-fixture variant — canonicalizes every fixture basename's absolute
    /// path (two-file tools like dicom-diff reference both operands).
    static func normalize(_ raw: String, fixtureBasenames: [String]) -> [String] {
        let decorations: Set<Character> = ["✅", "❌", "⚠", "️", "ℹ", "🔹", "▶", "›"]
        var lines: [String] = []
        for var line in raw.replacingOccurrences(of: "\r\n", with: "\n").split(separator: "\n", omittingEmptySubsequences: false).map(String.init) {
            // Strip ANSI color escape sequences — the CLI colorizes (e.g. dicom-dump)
            // while the app renders plain text; they should compare equal.
            line = line.replacingOccurrences(of: "\u{001B}\\[[0-9;]*m", with: "", options: .regularExpression)
            // Canonicalize volatile log timestamps (e.g. dicom-script --verbose's
            // "[2026-06-09 17:05:19] …") — the same line minted in the CLI and app runs
            // differs only by the wall-clock second.
            line = line.replacingOccurrences(of: "\\[[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2}\\]", with: "[<timestamp>]", options: .regularExpression)
            // ISO-8601 timestamps (e.g. dicom-anon's audit log "2026-06-10T05:40:57Z").
            line = line.replacingOccurrences(of: "[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z", with: "<timestamp>", options: .regularExpression)
            // The OUTPUT2 secondary-output scratch path (e.g. dicom-pdf --extract's
            // "Extracted: …/output2.dat") differs per side — canonicalize it.
            line = line.replacingOccurrences(of: "/[^\\s\"]*output2\\.dat", with: "<output2>", options: .regularExpression)
            // Volatile network timing — the in-app run and the CLI run are two SEPARATE
            // operations against the PACS, so per-op round-trip times, durations, and
            // throughput legitimately differ by wall-clock and must not show as diffs
            // (same philosophy as the timestamp mask). Byte COUNTS are deterministic
            // (identical files/datasets on both sides) and are deliberately NOT masked:
            // a "/s" throughput is masked, a plain "1.23 MB" size is left intact. The
            // seconds form requires a decimal point so an integer "Timeout: 30s" (which
            // is identical on both sides anyway) is left untouched.
            line = line.replacingOccurrences(of: "[0-9]+(\\.[0-9]+)?\\s?(ms|µs|us)\\b", with: "<dur>", options: .regularExpression)
            line = line.replacingOccurrences(of: "[0-9]+(\\.[0-9]+)?\\s?[KMGT]?B/s", with: "<rate>", options: .regularExpression)
            line = line.replacingOccurrences(of: "[0-9]+\\.[0-9]+\\s?s\\b", with: "<dur>", options: .regularExpression)
            // Drop the command-echo line Studio prepends.
            if line.hasPrefix("$ ") { continue }
            // Canonicalize any absolute path ending in a fixture basename. Match the
            // path prefix with [^\s"]* (not \S*) so a leading JSON quote isn't consumed
            // — otherwise "file":"/abs/syn-ct.dcm" → "file":syn-ct.dcm" breaks JSON parsing.
            for bn in fixtureBasenames where !bn.isEmpty && line.contains(bn) {
                let escaped = NSRegularExpression.escapedPattern(for: bn)
                line = line.replacingOccurrences(of: "[^\\s\"]*" + escaped, with: bn, options: .regularExpression)
            }
            line.removeAll { decorations.contains($0) }
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            // Drop the Studio-appended exit-code trailer (e.g. "Exit code: 0 (success)").
            // The real CLI conveys exit status via the process code, never on stdout.
            if trimmed.range(of: "^Exit code: -?[0-9]+\\b", options: .regularExpression) != nil { continue }
            // Canonicalize horizontal-rule separator lines: the CLI draws them with
            // box-drawing glyphs (═, ─) while Studio uses ASCII (=, -). Same meaning.
            if trimmed.count >= 3, trimmed.range(of: "^[═─=_-]+$", options: .regularExpression) != nil {
                lines.append("───"); continue
            }
            lines.append(trimmed)
        }
        // Trim leading/trailing blank lines.
        while let f = lines.first, f.isEmpty { lines.removeFirst() }
        while let l = lines.last, l.isEmpty { lines.removeLast() }
        // Collapse consecutive blank lines — concatenated multi-file dumps can have a
        // differing blank-run structure between the binary and the in-app re-dump
        // (the latter's stripped "Exit code:" trailer leaves a trailing blank per file).
        var collapsed: [String] = []
        for l in lines where !(l.isEmpty && collapsed.last == "") { collapsed.append(l) }
        lines = collapsed

        // JSON canonicalization: if the whole block is JSON, re-emit with sorted
        // keys so non-deterministic key order (on either side) doesn't show as a
        // diff. Non-JSON output falls through unchanged.
        let joined = lines.joined(separator: "\n")
        if let d = joined.data(using: .utf8),
           let obj = try? JSONSerialization.jsonObject(with: d),
           let out = try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys]),
           let str = String(data: out, encoding: .utf8) {
            return str.split(separator: "\n", omittingEmptySubsequences: false)
                .map { $0.trimmingCharacters(in: .whitespaces) }
        }
        return lines
    }

    /// Locates a `dicom-*` executable. Resolution order:
    ///   0. `preferredDir` (e.g. a freshly-built bin dir) — wins so a stale binary
    ///      elsewhere on disk can never shadow it
    ///   1. `DICOM_CLI_BIN_DIR` env var (directory holding the binaries)
    ///   2. SwiftPM build products under **this** checkout (`CLIToolBuilder.repoRoot()`) —
    ///      the **most-recently-built** of `.build/release|debug/<tool>` (so a stale config
    ///      can't shadow a fresh one)
    ///   3. `$PATH` and common install locations
    static func locateBinary(tool: String, preferredDir: String? = nil) -> String? {
        let fm = FileManager.default

        if let dir = preferredDir {
            let p = "\(dir)/\(tool)"
            if fm.isExecutableFile(atPath: p) { return p }
        }

        if let dir = ProcessInfo.processInfo.environment["DICOM_CLI_BIN_DIR"] {
            let p = "\(dir)/\(tool)"
            if fm.isExecutableFile(atPath: p) { return p }
        }

        func mtime(_ path: String) -> Date {
            ((try? fm.attributesOfItem(atPath: path))?[.modificationDate] as? Date) ?? .distantPast
        }

        var candidates: [String] = []
        // One source of truth for the checkout — resolving it here independently is how a
        // sibling repo's stale binaries ended up shadowing this one's.
        let repoRoots = [CLIToolBuilder.repoRoot()].compactMap { $0 }
        for root in repoRoots {
            // Prefer whichever of release/debug was built most recently. Otherwise a
            // stale `.build/release` (not rebuilt after a source change, while
            // `swift build` only refreshed debug) silently shadows the fresh binary —
            // which is exactly why the terminal / "Compare CLI" output diverged from
            // the source while the parity (which rebuilds first) stayed correct.
            let rel = "\(root)/.build/release/\(tool)"
            let dbg = "\(root)/.build/debug/\(tool)"
            candidates += [rel, dbg].sorted { mtime($0) > mtime($1) }
        }
        candidates += ["/usr/local/bin/\(tool)", "/opt/homebrew/bin/\(tool)"]

        for c in candidates where fm.isExecutableFile(atPath: c) { return c }

        if let path = ProcessInfo.processInfo.environment["PATH"] {
            for dir in path.split(separator: ":") {
                let full = "\(dir)/\(tool)"
                if fm.isExecutableFile(atPath: full) { return full }
            }
        }
        return nil
    }

    /// Runs `<tool> <arguments>` and captures stdout/stderr. `binDir`, when set,
    /// pins the binary to a specific directory (e.g. a freshly-built one). `timeout`,
    /// when set, is a wall-clock backstop: a network tool can block past its own
    /// connect timeout if the PACS accepts TCP but never answers a DIMSE request, so
    /// past the deadline the child is terminated (then hard-killed) and the outcome is
    /// marked timed-out — otherwise the whole parity run would freeze. `stdin`, when
    /// set, is written to the child's standard input then closed — this answers an
    /// interactive prompt (e.g. dicom-qr `--interactive`'s study-selection `readLine()`)
    /// deterministically, so the same answer drives the CLI and the SDK reference.
    static func run(tool: String, arguments: [String], binDir: String? = nil,
                    timeout: TimeInterval? = nil, stdin: String? = nil) -> Outcome {
        guard let bin = locateBinary(tool: tool, preferredDir: binDir) else {
            return Outcome(
                binaryPath: nil, stdout: "", stderr: "", exitCode: -1,
                launchError: "\(tool) binary not found. Build it with `swift build --product \(tool)`, or set DICOM_CLI_BIN_DIR to the directory containing the dicom-* binaries.")
        }

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: bin)
        proc.arguments = arguments
        let outPipe = Pipe()
        let errPipe = Pipe()
        proc.standardOutput = outPipe
        proc.standardError = errPipe
        // Feed the interactive answer (if any) on stdin so a `readLine()` prompt doesn't
        // block forever. Without a stdin pipe the child inherits the app's, which has no
        // input — an interactive tool would then hang until the timeout backstop fires.
        let inPipe: Pipe? = stdin != nil ? Pipe() : nil
        if let inPipe { proc.standardInput = inPipe }

        do {
            try proc.run()
        } catch {
            return Outcome(
                binaryPath: bin, stdout: "", stderr: "", exitCode: -1,
                launchError: "Failed to launch \(tool): \(error.localizedDescription). Is the App Sandbox disabled?")
        }

        // Write the interactive answer then close stdin (EOF) so the child's readLine()
        // returns. The tool may prompt only after its query completes, so the handle is
        // kept open until here; closing signals end-of-input for any further reads.
        if let inPipe, let stdin {
            let handle = inPipe.fileHandleForWriting
            handle.write(Data(stdin.utf8))
            try? handle.close()
        }

        // Drain both pipes concurrently. Reading them sequentially can deadlock
        // when the child fills the stderr buffer (~64 KB) while we're still blocked
        // reading stdout — neither side can make progress. A background read of
        // stderr removes that hazard for large outputs.
        // The DispatchGroup signal->wait is a happens-before edge, so these
        // manually synchronized captures are visible after group.wait().
        nonisolated(unsafe) var outData = Data()
        nonisolated(unsafe) var errData = Data()
        let group = DispatchGroup()
        let queue = DispatchQueue(label: "dicomkit.cli-compare.pipe-read", attributes: .concurrent)
        queue.async(group: group) { outData = outPipe.fileHandleForReading.readDataToEndOfFile() }
        queue.async(group: group) { errData = errPipe.fileHandleForReading.readDataToEndOfFile() }

        var timedOut = false
        if let timeout {
            if group.wait(timeout: .now() + timeout) == .timedOut {
                timedOut = true
                proc.terminate()                                  // SIGTERM
                if group.wait(timeout: .now() + 3) == .timedOut {
                    kill(proc.processIdentifier, SIGKILL)         // escalate if it ignores SIGTERM
                    group.wait()
                }
            }
        } else {
            group.wait()
        }
        proc.waitUntilExit()

        let stdout = String(data: outData, encoding: .utf8) ?? ""
        let stderr = String(data: errData, encoding: .utf8) ?? ""
        if timedOut {
            return Outcome(
                binaryPath: bin, stdout: stdout, stderr: stderr, exitCode: -2,
                launchError: "\(tool) exceeded \(Int(timeout ?? 0))s and was terminated — the PACS likely accepted the connection but never answered the DIMSE request.")
        }
        return Outcome(
            binaryPath: bin, stdout: stdout, stderr: stderr,
            exitCode: proc.terminationStatus, launchError: nil)
    }
}

#endif
