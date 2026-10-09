// NEMA-verified: 2026a, checked 2026-10-01 — edits go through TagEditRules (D150): --set writes the PS3.6 dictionary VR within the PS3.5 2026a Table 6.2-1 limits, group 0002 refused per PS3.10 7.1, Items/delimiters per PS3.5 7.5, unused groups and Private Creator naming per PS3.5 7.8.1 (D146)
import Foundation
import DICOMCore
import DICOMDictionary

/// Errors for tag-editing operations.
///
/// The engine itself never throws on an unresolved tag (it skips with a
/// description, see ``TagEditor/applyChanges(to:sets:deletes:deletePrivate:sourceDataSet:copyTags:verbose:dryRun:)``);
/// these cases are for adapters that want to fail fast on missing files or an
/// empty operation list.
public enum TagEditorError: Error, LocalizedError {
    case fileNotFound(String)
    case noOperationsSpecified
    case writeError(String)

    public var errorDescription: String? {
        switch self {
        case .fileNotFound(let path):
            return "File not found: \(path)"
        case .noOperationsSpecified:
            return "No operations specified. Use --set, --delete, --delete-private, or --copy-from"
        case .writeError(let msg):
            return "Write error: \(msg)"
        }
    }
}

/// Core tag-editing engine: parses tag specifiers and applies set / delete /
/// delete-private / copy operations to a `DataSet`.
///
/// Tag names and VRs are resolved through `DataElementDictionary` (the full DICOM
/// data dictionary), and an unresolved specifier is skipped with a note rather
/// than aborting the whole edit — so one bad tag never discards otherwise-valid
/// changes. Shared by the `dicom-tags` CLI and DICOMStudio so they cannot drift.
public struct TagEditor {

    public init() {}

    /// Parse a tag specifier: `PatientName`, `0010,0010`, `(0010,0010)`, or `00100010`.
    /// Returns `nil` for an unresolved name or malformed hex.
    public func parseTagSpecifier(_ spec: String) -> Tag? {
        let t = spec.trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: "(", with: "")
            .replacingOccurrences(of: ")", with: "")
        if t.contains(",") {
            let parts = t.split(separator: ",")
            if parts.count == 2,
               let g = UInt16(parts[0].trimmingCharacters(in: .whitespaces), radix: 16),
               let e = UInt16(parts[1].trimmingCharacters(in: .whitespaces), radix: 16) {
                return Tag(group: g, element: e)
            }
        } else if t.count == 8, t.allSatisfy({ $0.isHexDigit }), let v = UInt32(t, radix: 16) {
            return Tag(group: UInt16((v >> 16) & 0xFFFF), element: UInt16(v & 0xFFFF))
        }
        // Tag-name lookup via the full DICOM dictionary.
        return DataElementDictionary.lookup(keyword: t)?.tag
    }

    /// Apply all tag operations to `dataSet`, returning a human-readable
    /// description of each change. Order matches `dicom-tags`: deletes, then
    /// delete-private, then copies, then sets (so `--set` overrides a copied
    /// value). Unknown/invalid specifiers are skipped with a note.
    ///
    /// The ``TagEditRules`` apply (D150): a set writes the PS3.6 dictionary VR (binary
    /// for US, SS, UL, SL, FL, FD) and only a value within the PS3.5 2026a Table 6.2-1
    /// limits of that VR; group 0002 (PS3.10 7.1), Items and delimiters (PS3.5 7.5) and
    /// the groups PS3.5 7.8.1 says shall not be used are not set, deleted or copied.
    /// Here each refused change is skipped with a "(refused: …)" line and the others are
    /// applied; ``applyCheckedChanges(to:sets:deletes:deletePrivate:sourceDataSet:copyTags:verbose:dryRun:)``
    /// instead refuses the whole edit (what `dicom-tags` does).
    ///
    /// - Parameters:
    ///   - copyTags: tag specifiers to copy from `sourceDataSet`; empty means copy
    ///     every tag in the source.
    ///   - verbose: when deleting private tags, list each one instead of a count.
    ///   - dryRun: compute and describe changes without mutating `dataSet`.
    public func applyChanges(
        to dataSet: inout DataSet,
        sets: [String],
        deletes: [String],
        deletePrivate: Bool,
        sourceDataSet: DataSet?,
        copyTags: [String],
        verbose: Bool,
        dryRun: Bool
    ) -> [String] {
        // A non-strict pass never throws.
        (try? apply(to: &dataSet, sets: sets, deletes: deletes, deletePrivate: deletePrivate,
                    sourceDataSet: sourceDataSet, copyTags: copyTags, verbose: verbose,
                    dryRun: dryRun, strict: false)) ?? []
    }

    /// Like ``applyChanges(to:sets:deletes:deletePrivate:sourceDataSet:copyTags:verbose:dryRun:)``,
    /// but the first change the ``TagEditRules`` refuse throws a ``TagEditRefusal`` and
    /// `dataSet` is left untouched — no half-applied edit (D150).
    public func applyCheckedChanges(
        to dataSet: inout DataSet,
        sets: [String],
        deletes: [String],
        deletePrivate: Bool,
        sourceDataSet: DataSet?,
        copyTags: [String],
        verbose: Bool,
        dryRun: Bool
    ) throws -> [String] {
        var working = dataSet
        let lines = try apply(to: &working, sets: sets, deletes: deletes, deletePrivate: deletePrivate,
                              sourceDataSet: sourceDataSet, copyTags: copyTags, verbose: verbose,
                              dryRun: dryRun, strict: true)
        if !dryRun { dataSet = working }
        return lines
    }

    private func apply(
        to dataSet: inout DataSet,
        sets: [String],
        deletes: [String],
        deletePrivate: Bool,
        sourceDataSet: DataSet?,
        copyTags: [String],
        verbose: Bool,
        dryRun: Bool,
        strict: Bool
    ) throws -> [String] {
        var descriptions: [String] = []

        // In strict mode every named tag is checked before anything changes.
        if strict {
            let named = deletes + copyTags + sets.compactMap { spec in
                spec.range(of: "=").map { String(spec[..<$0.lowerBound]) }
            }
            for spec in named {
                if let tag = parseTagSpecifier(spec), let reason = TagEditRules.dataSetRefusal(for: tag) {
                    throw TagEditRefusal(reason)
                }
            }
        }

        // 1. Deletes
        for deleteSpec in deletes {
            if let tag = parseTagSpecifier(deleteSpec) {
                let label = self.label(for: tag)
                if let reason = TagEditRules.dataSetRefusal(for: tag) {
                    descriptions.append("DELETE \(label) (refused: \(reason))")
                } else if dataSet[tag] != nil {
                    if !dryRun { dataSet.remove(tag: tag) }
                    descriptions.append("DELETE \(label)")
                } else {
                    descriptions.append("DELETE \(label) (not present, skipped)")
                }
            } else {
                descriptions.append("DELETE \(deleteSpec) (unknown tag, skipped)")
            }
        }

        // 2. Delete private tags
        if deletePrivate {
            var removed = 0
            for tag in dataSet.tags where tag.isOddGroup {  // private, and the unusable odd groups (PS3.5 7.8.1)
                if !dryRun { dataSet.remove(tag: tag) }
                removed += 1
                if verbose { descriptions.append("DELETE private tag \(self.label(for: tag))") }
            }
            if !verbose { descriptions.append("DELETE \(removed) private tag(s)") }
        }

        // 3. Copy tags from source
        if let source = sourceDataSet {
            let tagsToCopy: [Tag] = copyTags.isEmpty
                ? source.tags
                : copyTags.compactMap { parseTagSpecifier($0) }
            for tag in tagsToCopy {
                if let element = source[tag] {
                    let label = self.label(for: tag)
                    if let reason = TagEditRules.dataSetRefusal(for: tag) {
                        descriptions.append("COPY \(label) (refused: \(reason))")
                        continue
                    }
                    if !dryRun { dataSet[tag] = element }
                    let value = element.stringValue ?? "<binary>"
                    descriptions.append("COPY \(label) = \(value)")
                }
            }
        }

        // 4. Set values (last, so they override copies). In strict mode every value is
        //    checked before any is written.
        var pending: [DataElement] = []
        for setSpec in sets {
            if let eqRange = setSpec.range(of: "=") {
                let tagPart   = String(setSpec[..<eqRange.lowerBound])
                let valuePart = String(setSpec[eqRange.upperBound...])
                if let tag = parseTagSpecifier(tagPart) {
                    let label = self.label(for: tag)
                    if let reason = TagEditRules.dataSetRefusal(for: tag) {
                        descriptions.append("SET \(label) (refused: \(reason))")
                        continue
                    }
                    let vr = TagEditRules.writeVR(for: tag, existing: dataSet[tag]?.vr)
                    switch TagEditRules.element(tag: tag, vr: vr, text: valuePart) {
                    case .success(let element):
                        if strict { pending.append(element) } else if !dryRun { dataSet[tag] = element }
                        descriptions.append("SET \(label) = \(valuePart)")
                    case .failure(let refusal):
                        if strict { throw refusal }
                        descriptions.append("SET \(label) (refused: \(refusal.message))")
                    }
                } else {
                    descriptions.append("SET \(tagPart) (unknown tag, skipped)")
                }
            } else {
                descriptions.append("SET \(setSpec) (invalid format, expected TagName=Value)")
            }
        }
        if !dryRun {
            for element in pending { dataSet[element.tag] = element }
        }

        return descriptions
    }

    // MARK: - Helpers

    /// `(GGGG,EEEE) Name` using the PS3.6 name (or "Private Creator", PS3.5 7.8.1) when
    /// known, else just the hex.
    private func label(for tag: Tag) -> String {
        TagEditRules.label(for: tag)
    }
}

// MARK: - Shared console lines

/// Console lines for `dicom-tags` — the single source of truth used by BOTH the
/// CLI and DICOMStudio's Workshop executor, so their output cannot drift.
/// (An earlier app copy printed an unconditional count line and "Saved:" where
/// the CLI prints "Output written to:".)
public enum TagEditConsole {
    /// The change-preview block: one line per change plus the count line,
    /// emitted only under `--verbose` or `--dry-run` (the CLI gate).
    public static func changesBlock(_ changes: [String], verbose: Bool, dryRun: Bool) -> String {
        guard verbose || dryRun else { return "" }
        var out = ""
        for change in changes { out += change + "\n" }
        out += "\(changes.count) change(s) applied.\n"
        return out
    }

    /// The completion line: dry-run notice, or the written-output path.
    public static func completionLine(dryRun: Bool, outputPath: String) -> String {
        dryRun ? "Dry run complete — no files modified.\n"
               : "Output written to: \(outputPath)\n"
    }
}
