// IntegratedTerminalHelpers.swift
// DICOMStudio
//
// DICOM Studio — Helpers for Integrated Terminal & Command Execution (Milestone 20)
// NEMA-verified: 2026a, checked 2026-10-05 — the 7 redactPHI keywords resolved through PS3.6 2026a Table 6-1 to attribute names and each found as a row of PS3.15 2026a Table E.1-1 (Basic Application Level Confidentiality Profile): 7 of 7 match; the ANSI SGR codes, tokeniser, history and environment helpers carry no DICOM-standard data

import Foundation

// MARK: - Navigation Direction

/// Direction used to navigate through command history.
public enum NavigationDirection: Sendable, Equatable {
    /// Move to an earlier (older) history entry.
    case up
    /// Move to a later (newer) history entry.
    case down
}

// MARK: - Syntax Highlighting Helpers

/// Platform-independent helpers for tokenising CLI command strings for syntax highlighting.
public enum SyntaxHighlightingHelpers: Sendable {

    /// Parses a raw command string into a sequence of ``SyntaxToken`` values.
    ///
    /// Tokenisation rules (applied left to right, one token per whitespace-delimited word):
    /// - The first word becomes `.toolName`.
    /// - Words that start with `--` or `-` become `.flag`.
    /// - A word that immediately follows a flag and does not start with `-` becomes `.value`.
    /// - Words that look like file paths (contain `/`, start with `~`, or end with `.dcm`) become `.filePath`.
    /// - `|`, `>`, `>>`, and `<` become `.pipeOrRedirect`.
    /// - Everything else becomes `.plain`.
    public static func tokenize(command: String) -> [SyntaxToken] {
        let words = command.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
        guard !words.isEmpty else { return [] }

        var tokens: [SyntaxToken] = []
        var previousWasFlag = false

        for (index, word) in words.enumerated() {
            let type: SyntaxTokenType
            if index == 0 {
                type = .toolName
                previousWasFlag = false
            } else if word == "|" || word == ">" || word == ">>" || word == "<" {
                type = .pipeOrRedirect
                previousWasFlag = false
            } else if word.hasPrefix("--") || (word.hasPrefix("-") && !word.hasPrefix("--")) {
                type = .flag
                previousWasFlag = true
            } else if previousWasFlag && !word.hasPrefix("-") {
                type = .value
                previousWasFlag = false
            } else if isFilePath(word) {
                type = .filePath
                previousWasFlag = false
            } else {
                type = .plain
                previousWasFlag = false
            }
            tokens.append(SyntaxToken(text: word, type: type))
        }

        return tokens
    }

    /// Builds a token array from a structured description of a command invocation.
    ///
    /// - Parameters:
    ///   - subcommand: An optional subcommand name, emitted as `.subcommand` after the tool name.
    ///   - params: Key/value pairs that are emitted as flag/value token pairs.
    ///   - flags: Boolean flags emitted as `.flag` tokens with no accompanying value.
    public static func tokenize(
        subcommand: String,
        params: [String: String],
        flags: [String]
    ) -> [SyntaxToken] {
        var tokens: [SyntaxToken] = []

        if !subcommand.isEmpty {
            tokens.append(SyntaxToken(text: subcommand, type: .subcommand))
        }

        for key in params.keys.sorted() {
            let flag = key.hasPrefix("-") ? key : "--\(key)"
            tokens.append(SyntaxToken(text: flag, type: .flag))
            if let value = params[key] {
                let tokenType: SyntaxTokenType = isFilePath(value) ? .filePath : .value
                tokens.append(SyntaxToken(text: value, type: tokenType))
            }
        }

        for flag in flags.sorted() {
            let flagText = flag.hasPrefix("-") ? flag : "--\(flag)"
            tokens.append(SyntaxToken(text: flagText, type: .flag))
        }

        return tokens
    }

    /// Returns `true` when `token` looks like a file-system path.
    ///
    /// A token is considered a path when it contains `/`, starts with `~`, or ends with `.dcm`.
    public static func isFilePath(_ token: String) -> Bool {
        token.contains("/") || token.hasPrefix("~") || token.lowercased().hasSuffix(".dcm")
    }
}

// MARK: - ANSI Parsing Helpers

/// Platform-independent helpers for parsing and stripping ANSI SGR escape sequences.
public enum ANSIParsingHelpers: Sendable {

    /// Parses ANSI SGR escape sequences in `text`, returning an array of (text, color?) segments.
    ///
    /// Supported SGR codes:
    /// - `30`–`37`: standard foreground colors (black … white)
    /// - `90`–`97`: bright foreground colors
    /// - `39`: default foreground (reset to `nil`)
    /// - `0` / `m` with no code: full reset
    ///
    /// Unrecognised codes leave the current color unchanged.
    public static func parseANSIEscapes(in text: String) -> [(text: String, color: ANSIColor?)] {
        var results: [(text: String, color: ANSIColor?)] = []
        var currentColor: ANSIColor? = nil
        var remaining = text[text.startIndex...]

        // Pattern: ESC [ <params> m
        let escapePrefix = "\u{1B}["

        while !remaining.isEmpty {
            guard let escRange = remaining.range(of: escapePrefix) else {
                // No more escapes — flush remaining text
                let chunk = String(remaining)
                if !chunk.isEmpty {
                    results.append((text: chunk, color: currentColor))
                }
                break
            }

            // Flush text before the escape sequence
            let before = String(remaining[remaining.startIndex..<escRange.lowerBound])
            if !before.isEmpty {
                results.append((text: before, color: currentColor))
            }

            // Advance past ESC[
            remaining = remaining[escRange.upperBound...]

            // Read up to and including the terminating 'm'
            guard let mRange = remaining.range(of: "m") else {
                // Malformed escape — consume what's left
                break
            }

            let params = String(remaining[remaining.startIndex..<mRange.lowerBound])
            remaining = remaining[mRange.upperBound...]

            // Parse semicolon-separated codes
            let codes = params.split(separator: ";", omittingEmptySubsequences: true)
            for codeStr in codes {
                guard let code = Int(codeStr) else { continue }
                if code == 0 || code == 39 {
                    currentColor = nil
                } else if let color = ansiColor(forCode: code) {
                    currentColor = color
                }
            }
            // A bare "ESC[m" (empty params) also resets
            if codes.isEmpty {
                currentColor = nil
            }
        }

        return results
    }

    /// Returns `text` with all ANSI escape sequences removed.
    public static func stripANSI(from text: String) -> String {
        var result = ""
        var remaining = text[text.startIndex...]
        let escapePrefix = "\u{1B}["

        while !remaining.isEmpty {
            guard let escRange = remaining.range(of: escapePrefix) else {
                result += remaining
                break
            }
            result += remaining[remaining.startIndex..<escRange.lowerBound]
            remaining = remaining[escRange.upperBound...]

            // Skip to the terminating 'm'
            if let mRange = remaining.range(of: "m") {
                remaining = remaining[mRange.upperBound...]
            } else {
                break
            }
        }

        return result
    }

    /// Returns the ANSI SGR foreground code for `color`.
    ///
    /// Standard colors map to codes `30`–`37`; bright colors map to `90`–`97`.
    public static func ansiCode(for color: ANSIColor) -> Int {
        switch color {
        case .black:         return 30
        case .red:           return 31
        case .green:         return 32
        case .yellow:        return 33
        case .blue:          return 34
        case .magenta:       return 35
        case .cyan:          return 36
        case .white:         return 37
        case .brightBlack:   return 90
        case .brightRed:     return 91
        case .brightGreen:   return 92
        case .brightYellow:  return 93
        case .brightBlue:    return 94
        case .brightMagenta: return 95
        case .brightCyan:    return 96
        case .brightWhite:   return 97
        }
    }

    // MARK: Private

    private static func ansiColor(forCode code: Int) -> ANSIColor? {
        switch code {
        case 30: return .black
        case 31: return .red
        case 32: return .green
        case 33: return .yellow
        case 34: return .blue
        case 35: return .magenta
        case 36: return .cyan
        case 37: return .white
        case 90: return .brightBlack
        case 91: return .brightRed
        case 92: return .brightGreen
        case 93: return .brightYellow
        case 94: return .brightBlue
        case 95: return .brightMagenta
        case 96: return .brightCyan
        case 97: return .brightWhite
        default: return nil
        }
    }
}

// MARK: - Terminal Command Builder Helpers

/// Platform-independent helpers for constructing CLI command strings from the integrated terminal.
public enum TerminalCommandBuilderHelpers: Sendable {

    /// Maximum number of bytes of tool output that DICOM Studio will buffer in memory (10 MB).
    public static let maxOutputBytes: Int = 10_485_760

    /// Builds a complete shell command string from its constituent parts.
    ///
    /// - Parameters:
    ///   - toolName: The executable name (e.g. `"dicom-query"`).
    ///   - subcommand: An optional subcommand inserted immediately after the tool name.
    ///   - params: Key/value parameters; each pair is rendered as `--key value`.
    ///   - flags: Boolean flags rendered as `--flag` (no value).
    ///   - positionalArgs: Positional arguments appended at the end; paths with spaces are quoted.
    public static func build(
        toolName: String,
        subcommand: String?,
        params: [String: String],
        flags: [String],
        positionalArgs: [String]
    ) -> String {
        var parts: [String] = [toolName]

        if let sub = subcommand, !sub.isEmpty {
            parts.append(sub)
        }

        for key in params.keys.sorted() {
            let flag = key.hasPrefix("-") ? key : "--\(key)"
            parts.append(flag)
            if let value = params[key] {
                parts.append(quoteIfNeeded(value))
            }
        }

        for flag in flags.sorted() {
            let flagText = flag.hasPrefix("-") ? flag : "--\(flag)"
            parts.append(flagText)
        }

        for arg in positionalArgs {
            parts.append(quoteIfNeeded(arg))
        }

        return parts.joined(separator: " ")
    }

    /// Wraps `value` in double quotes when it contains whitespace; escapes any embedded double
    /// quotes and backslashes so the resulting shell token is well-formed.
    public static func quoteIfNeeded(_ value: String) -> String {
        if value.contains(" ") || value.contains("\t") {
            let escaped = value
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "\"", with: "\\\"")
            return "\"\(escaped)\""
        }
        return value
    }

    /// Builds a command that operates on multiple input files with an optional output path.
    ///
    /// - Parameters:
    ///   - toolName: The executable name.
    ///   - subcommand: An optional subcommand.
    ///   - files: Input file paths; paths with spaces are quoted automatically.
    ///   - outputPath: An optional `--output` destination path.
    ///   - extraParams: Additional `--key value` parameters.
    public static func buildMultiFileCommand(
        toolName: String,
        subcommand: String?,
        files: [String],
        outputPath: String?,
        extraParams: [String: String]
    ) -> String {
        var params = extraParams
        if let output = outputPath, !output.isEmpty {
            params["output"] = output
        }
        return TerminalCommandBuilderHelpers.build(
            toolName: toolName,
            subcommand: subcommand,
            params: params,
            flags: [],
            positionalArgs: files
        )
    }
}

// MARK: - Command History Helpers

/// Platform-independent helpers for managing and navigating command history.
public enum CommandHistoryHelpers: Sendable {

    /// Replaces file-path tokens and patient-identifying patterns in `command` with placeholders.
    ///
    /// - Tokens that contain `/` are replaced with `<path>`.
    /// - DICOM attribute assignments matching 7 identifying attributes of PS3.15 Table E.1-1 (PatientName,
    ///   PatientID, PatientBirthDate, AccessionNumber, StudyInstanceUID, SeriesInstanceUID,
    ///   SOPInstanceUID) are replaced with `<attribute>=<redacted>`.
    public static func redactPHI(from command: String) -> String {
        // Replace path-looking tokens
        let words = command.components(separatedBy: .whitespaces)
        let redactedWords = words.map { word -> String in
            if !word.hasPrefix("-") && word.contains("/") {
                return "<path>"
            }
            return word
        }
        var result = redactedWords.joined(separator: " ")

        // PS3.15 2026a Table E.1-1 attributes (PS3.6 Table 6-1 keywords) whose values the history must not keep
        let phiAttributes = [
            "PatientName",
            "PatientID",
            "PatientBirthDate",
            "AccessionNumber",
            "StudyInstanceUID",
            "SeriesInstanceUID",
            "SOPInstanceUID",
        ]
        for attribute in phiAttributes {
            if let regex = try? NSRegularExpression(
                pattern: "(?i)\(attribute)\\s*=\\s*\\S+",
                options: []
            ) {
                result = regex.stringByReplacingMatches(
                    in: result,
                    range: NSRange(result.startIndex..., in: result),
                    withTemplate: "\(attribute)=<redacted>"
                )
            }
        }

        return result
    }

    /// Returns the path to the DICOM Studio command history file.
    ///
    /// Resolves the Application Support directory via `FileManager` for correct cross-platform
    /// behaviour; falls back to `~/Library/Application Support/DICOMStudio/history.json` when
    /// the directory cannot be resolved.
    public static func historyFilePath() -> String {
        let fallback = (
            "~/Library/Application Support/DICOMStudio/history.json" as NSString
        ).expandingTildeInPath
        guard let appSupport = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        else { return fallback }
        return appSupport
            .appendingPathComponent("DICOMStudio", isDirectory: true)
            .appendingPathComponent("history.json")
            .path
    }

    /// Filters `entries` according to `filter`, returning only the matching entries.
    ///
    /// - A non-nil `filter.toolName` restricts results to entries with a matching tool name.
    /// - A non-empty `filter.searchText` performs a case-insensitive substring match on the command.
    /// - When `filter.showSuccessOnly` is `true`, only entries with exit code `0` are included.
    public static func filter(
        entries: [CommandHistoryEntry],
        by filter: CommandHistoryFilter
    ) -> [CommandHistoryEntry] {
        var result = entries

        if let toolName = filter.toolName, !toolName.isEmpty {
            result = result.filter { $0.toolName == toolName }
        }

        if !filter.searchText.isEmpty {
            result = result.filter {
                $0.command.localizedCaseInsensitiveContains(filter.searchText)
            }
        }

        if filter.showSuccessOnly {
            result = result.filter { $0.isSuccess }
        }

        return result
    }

    /// Returns a new ``CommandHistoryState`` after navigating one step in `direction`.
    ///
    /// - `.up` moves toward older entries (increasing index).
    /// - `.down` moves toward newer entries (decreasing index), resetting to `nil` at the end.
    public static func navigate(
        history: CommandHistoryState,
        direction: NavigationDirection
    ) -> CommandHistoryState {
        let count = history.entries.count
        guard count > 0 else { return history }

        var newState = history

        switch direction {
        case .up:
            if let current = history.currentIndex {
                newState.currentIndex = min(current + 1, count - 1)
            } else {
                newState.currentIndex = 0
            }
        case .down:
            if let current = history.currentIndex {
                newState.currentIndex = current > 0 ? current - 1 : nil
            }
        }

        return newState
    }
}

// MARK: - Execution Helpers

/// Platform-independent helpers for configuring and measuring command execution.
public enum ExecutionHelpers: Sendable {

    /// Expands a leading `~` in `path` to the current user's home directory.
    ///
    /// Uses `NSString.expandingTildeInPath` for correct cross-platform path construction.
    public static func expandTilde(in path: String) -> String {
        (path as NSString).expandingTildeInPath
    }

    /// Builds a process environment dictionary from `base`, prepending `additionalPath` to `PATH`
    /// and setting `TERM` and `COLUMNS` from ``ExecutorEnvironment``.
    ///
    /// - Parameters:
    ///   - base: The starting environment (typically `ProcessInfo.processInfo.environment`).
    ///   - additionalPath: A directory to prepend to the `PATH` variable.
    public static func buildEnvironment(
        base: [String: String],
        adding additionalPath: String
    ) -> [String: String] {
        var env = base
        let existing = env["PATH"] ?? "/usr/local/bin:/usr/bin:/bin"
        let expanded = expandTilde(in: additionalPath)
        env["PATH"] = expanded.isEmpty ? existing : "\(expanded):\(existing)"

        let defaults = ExecutorEnvironment()
        env["TERM"] = defaults.termType
        env["COLUMNS"] = "\(defaults.columns)"

        return env
    }

    /// Formats a duration in seconds as a compact human-readable string.
    ///
    /// Examples: `"0.5s"`, `"12s"`, `"1m 30s"`.
    public static func formatDuration(_ seconds: TimeInterval) -> String {
        if seconds < 60 {
            let formatted = seconds.truncatingRemainder(dividingBy: 1) == 0
                ? String(Int(seconds)) + "s"
                : String(format: "%.1fs", seconds)
            return formatted
        }
        let minutes = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return secs == 0 ? "\(minutes)m" : "\(minutes)m \(secs)s"
    }

    /// Returns the maximum number of output lines that should be retained in a rolling buffer
    /// of `bufferBytes` bytes, given an `avgLineLength` estimate.
    ///
    /// The result is always at least `1`.
    public static func maxBufferLines(for bufferBytes: Int, avgLineLength: Int) -> Int {
        guard avgLineLength > 0, bufferBytes > 0 else { return 1 }
        return max(1, bufferBytes / avgLineLength)
    }
}

// MARK: - Terminal Display Helpers

/// Platform-independent helpers for terminal display layout and theming.
public enum TerminalDisplayHelpers: Sendable {

    /// Clamps a proposed terminal panel height between `min` and a fraction of the total height.
    ///
    /// - Parameters:
    ///   - height: The proposed height in points.
    ///   - min: The minimum allowable height.
    ///   - maxFraction: The maximum height expressed as a fraction of `totalHeight` (e.g. `0.7`).
    ///   - totalHeight: The total available height of the containing view.
    public static func clampHeight(
        _ height: Double,
        min: Double,
        maxFraction: Double,
        of totalHeight: Double
    ) -> Double {
        let maxHeight = totalHeight * maxFraction
        return Swift.max(min, Swift.min(height, maxHeight))
    }

    /// Returns the default terminal font size in points.
    public static func defaultFontSize() -> Double {
        12.0
    }

    /// Suggests an appropriate ``TerminalColorScheme`` based on the current system appearance.
    ///
    /// - Parameter forSystemDark: `true` when the system is using a dark appearance.
    public static func colorSchemeSuggestion(forSystemDark: Bool) -> TerminalColorScheme {
        forSystemDark ? .dark : .light
    }
}
