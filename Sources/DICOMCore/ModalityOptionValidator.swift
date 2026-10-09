import Foundation

/// Shared validation and help text for a CLI `--modality` option.
///
/// Every `dicom-*` tool that accepts `--modality` runs its value through this,
/// so one answer to "is CT a modality?" serves the whole toolset. Before this
/// existed no CLI validated the option at all: a typo went to the PACS as a
/// filter that silently matched nothing.
///
/// Modality (0008,0060) is a *Defined Term* (PS3.3 C.7.3.1.1.1), not an
/// Enumerated Value, so an unrecognized code is legal and warns rather than
/// failing. `--strict-modality` promotes that warning to an error for callers
/// who would rather not discover a typo from an empty result set.
public enum ModalityOptionValidator: Sendable {

    /// What validating a `--modality` value produced.
    public struct Outcome: Sendable, Equatable {
        /// The value to use: the normalized code, or the input when unrecognized.
        public let value: String
        /// A human-readable warning for stderr, or `nil` when the value is clean.
        public let warning: String?
        /// Whether `--strict-modality` should turn this into an error.
        public let isStrictFailure: Bool
        /// Whether this is informational (an alias was normalized) rather than a problem.
        public let isNote: Bool

        public init(value: String, warning: String? = nil,
                    isStrictFailure: Bool = false, isNote: Bool = false) {
            self.value = value
            self.warning = warning
            self.isStrictFailure = isStrictFailure
            self.isNote = isNote
        }
    }

    /// Validates and normalizes a raw `--modality` value.
    ///
    /// - Alias (`MRI`, `PET`, `XR`, `RT`, …) → normalized, noted only at `--verbose`.
    /// - Retired code (`ST`, `MA`, …) → kept, warned, named as retired.
    /// - Unknown code → kept verbatim (it may be a legal private code), warned.
    /// - Current defined term → returned unchanged, no warning.
    ///
    /// - Parameter raw: The value as typed on the command line.
    /// - Returns: The outcome, or `nil` when `raw` is nil/empty (no filter).
    public static func validate(_ raw: String?) -> Outcome? {
        guard let raw, !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)

        // A known code: current, retired, or a conventional non-standard one.
        if let modality = Modality(rawValue: trimmed) {
            if modality.isRetired {
                return Outcome(
                    value: modality.rawValue,
                    warning: "modality '\(modality.rawValue)' (\(modality.name)) is retired "
                        + "in the DICOM standard.",
                    isStrictFailure: true)
            }
            if !modality.isStandard {
                return Outcome(
                    value: modality.rawValue,
                    warning: "modality '\(modality.rawValue)' is in common use but is not a "
                        + "DICOM Defined Term (PS3.3 C.7.3.1.1.1); for Secondary Capture the "
                        + "standard asks for the modality that originally created the data.",
                    isStrictFailure: true)
            }
            return Outcome(value: modality.rawValue)
        }

        // Not a code, but a spelling we recognize — normalize and say so.
        if let normalized = Modality.normalized(trimmed) {
            return Outcome(
                value: normalized.rawValue,
                warning: "note: '\(trimmed)' is not a DICOM modality code; using "
                    + "'\(normalized.rawValue)' (\(normalized.name)).",
                isNote: true)
        }

        // Unrecognized. Private codes are legal, so warn rather than reject,
        // and suggest the closest defined terms to catch an ordinary typo.
        var warning = "'\(trimmed)' is not a DICOM Defined Term (PS3.3 C.7.3.1.1.1)."
        let suggestions = closestCodes(to: trimmed)
        if !suggestions.isEmpty {
            warning += " Did you mean \(suggestions.joined(separator: ", "))?"
        }
        warning += " Run 'dicom-tags --list-modalities' to see every code."
        return Outcome(value: trimmed.uppercased(), warning: warning, isStrictFailure: true)
    }

    /// Up to three defined terms closest to a misspelling, by edit distance.
    static func closestCodes(to raw: String) -> [String] {
        let needle = raw.uppercased()
        var scored: [(code: String, distance: Int)] = []
        for modality in Modality.allCases {
            let distance = editDistance(needle, modality.rawValue)
            // A distance above 2 is a different code, not a typo of this one.
            if distance <= 2 {
                scored.append((code: modality.rawValue, distance: distance))
            }
        }
        scored.sort { lhs, rhs in
            lhs.distance == rhs.distance ? lhs.code < rhs.code : lhs.distance < rhs.distance
        }
        return scored.prefix(3).map { $0.code }
    }

    /// Levenshtein distance, for the "did you mean" suggestion only.
    private static func editDistance(_ a: String, _ b: String) -> Int {
        let a = Array(a), b = Array(b)
        if a.isEmpty { return b.count }
        if b.isEmpty { return a.count }
        var previous = Array(0...b.count)
        var current = [Int](repeating: 0, count: b.count + 1)
        for i in 1...a.count {
            current[0] = i
            for j in 1...b.count {
                let substitution = previous[j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1)
                current[j] = min(previous[j] + 1, current[j - 1] + 1, substitution)
            }
            swap(&previous, &current)
        }
        return previous[b.count]
    }

    // MARK: - CLI wiring

    /// Validates a `--modality` value, emits any warning to stderr, and returns
    /// the value to use.
    ///
    /// The one call each `dicom-*` tool needs. Warnings go to stderr so a piped
    /// stdout stays clean; `strict` turns a questionable value into a thrown
    /// error instead.
    ///
    /// - Parameters:
    ///   - raw: The raw option value.
    ///   - strict: Whether `--strict-modality` was given.
    ///   - verbose: Whether to print the alias-normalization note, which is
    ///     informational rather than a problem.
    /// - Returns: The normalized value, or `nil` when no modality was given.
    /// - Throws: ``ModalityOptionError/rejected(_:)`` when `strict` and the
    ///   value is not a current defined term.
    @discardableResult
    public static func resolve(
        _ raw: String?,
        strict: Bool = false,
        verbose: Bool = false
    ) throws -> String? {
        guard let outcome = validate(raw) else { return nil }
        if let warning = outcome.warning {
            if strict, outcome.isStrictFailure {
                // Under --strict-modality the value is rejected, so say that
                // rather than the non-strict "sending it as-is".
                throw ModalityOptionError.rejected(
                    warning + " Rejected because --strict-modality is set.")
            }
            // An alias note is informational; only surface it when asked.
            if !outcome.isNote || verbose {
                let text = outcome.isNote ? warning : "warning: " + warning + " Sending it as-is."
                FileHandle.standardError.write(Data((text + "\n").utf8))
            }
        }
        return outcome.value
    }

    // MARK: - Help text

    /// Help text for a `--modality` option, shared so the tools agree.
    ///
    /// - Parameter context: What the option does in this tool, e.g. `"filter"`.
    public static func helpText(_ context: String) -> String {
        "Modality \(context) (0008,0060) — e.g. CT, MR, US, OPT. "
            + "Run 'dicom-tags --list-modalities' for every DICOM 2026a code."
    }

    /// The full modality listing printed by `--list-modalities`.
    ///
    /// Grouped by category, because a flat run of 79 codes is unreadable.
    ///
    /// NEMA-verified: 2026a, checked 2026-09-24 — holds no term list of its own; every lookup goes
    /// through `Modality`, which is text-diffed against PS3.3 2026a.
    public static func listing() -> String {
        var lines: [String] = [
            "DICOM Modality codes (0008,0060) — PS3.3 C.7.3.1.1.1, 2026a",
            "",
        ]
        for group in Modality.groupedByCategory {
            lines.append("\(group.category.name):")
            for modality in group.modalities {
                let code = modality.rawValue.padding(toLength: 12, withPad: " ", startingAt: 0)
                lines.append("  \(code)\(modality.name)")
            }
            lines.append("")
        }
        lines.append("Retired codes are accepted for legacy data but not listed here.")
        lines.append("Aliases accepted and normalized: MRI→MR, PET→PT, PDF→DOC, "
                     + "XR/DR→DX, SPECT→NM, RT→RTIMAGE.")
        return lines.joined(separator: "\n")
    }
}

/// An error from a `--modality` value rejected under `--strict-modality`.
public enum ModalityOptionError: Error, CustomStringConvertible, Sendable {
    /// The value is not a current DICOM Defined Term.
    case rejected(String)

    public var description: String {
        switch self {
        case .rejected(let message): return message
        }
    }

    /// `LocalizedError`-style text, so ArgumentParser prints it cleanly.
    public var localizedDescription: String { description }
}
