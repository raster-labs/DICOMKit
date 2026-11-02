// NEMA-verified: 2026a, checked 2026-10-01 — edits go through TagEditRules (D150): --set writes the PS3.6 dictionary VR within the PS3.5 2026a Table 6.2-1 limits, group 0002 refused per PS3.10 7.1, Items/delimiters per PS3.5 7.5, unused groups and Private Creator naming per PS3.5 7.8.1 (D146)
import Foundation
import DICOMCore
import DICOMDictionary

/// Errors for tag-editing operations.
///
/// Adapter errors for missing files, an empty operation list, or failed writes.
/// Checked edits also throw `TagEditRefusal` for invalid selectors or values.
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
/// data dictionary). Checked edits refuse unresolved specifiers transactionally.
/// Shared by the `dicom-tags` CLI and DICOMStudio so they cannot drift.
public struct TagEditor {

    public init() {}

    /// Parse a tag specifier: `PatientName`, `0010,0010`, `(0010,0010)`, or `00100010`.
    /// Returns `nil` for an unresolved name or malformed hex.
    public func parseTagSpecifier(_ spec: String) -> Tag? {
        var t = spec.trimmingCharacters(in: .whitespaces)
        if t.hasPrefix("("), t.hasSuffix(")") { t = String(t.dropFirst().dropLast()) }
        if t.contains(",") {
            let parts = t.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            if parts.count == 2, parts.allSatisfy(Self.isHexWord),
               let g = UInt16(parts[0], radix: 16), let e = UInt16(parts[1], radix: 16) {
                return Tag(group: g, element: e)
            }
        } else if t.utf8.count == 8, t.utf8.allSatisfy(Self.isHex), let v = UInt32(t, radix: 16) {
            return Tag(group: UInt16(v >> 16), element: UInt16(v & 0xFFFF))
        }
        return DataElementDictionary.lookup(keyword: t)?.tag
    }

    /// Parse copy selectors without splitting a numeric GGGG,EEEE pair. Commas
    /// and semicolons separate selectors; numeric pairs may be parenthesized.
    /// Invalid or incomplete selectors are refused instead of becoming a no-op.
    public func parseTagSelectors(_ text: String) throws -> [String] {
        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return [] }
        var result: [String] = []
        for list in text.components(separatedBy: ";") {
            var parts: [String] = [], token = "", depth = 0
            for character in list {
                if character == "(" { depth += 1 }
                if character == ")" { depth -= 1 }
                guard (0...1).contains(depth) else { throw TagEditRefusal("Invalid copy selector: \(text)") }
                if character == ",", depth == 0 { parts.append(token); token = "" }
                else { token.append(character) }
            }
            guard depth == 0 else { throw TagEditRefusal("Invalid copy selector: \(text)") }
            parts.append(token)
            parts = parts.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            var index = 0
            while index < parts.count {
                var specifier = parts[index]
                if Self.isHexWord(specifier), index + 1 < parts.count, Self.isHexWord(parts[index + 1]) {
                    specifier += "," + parts[index + 1]
                    index += 1
                }
                guard let tag = parseTagSpecifier(specifier) else {
                    throw TagEditRefusal("Unknown or malformed copy selector: \(String(reflecting: specifier))")
                }
                result.append(String(format: "%04X%04X", tag.group, tag.element))
                index += 1
            }
        }
        return result
    }

    private static func isHex(_ byte: UInt8) -> Bool {
        (48...57).contains(byte) || (65...70).contains(byte) || (97...102).contains(byte)
    }

    private static func isHexWord(_ value: String) -> Bool {
        value.utf8.count == 4 && value.utf8.allSatisfy(isHex)
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
        do {
            var working = try normalizedDestination(dataSet)
            let source = try normalizedCopySource(sourceDataSet)
            let lines = try apply(to: &working, sets: sets, deletes: deletes, deletePrivate: deletePrivate,
                                  sourceDataSet: source, copyTags: copyTags, verbose: verbose, strict: false)
            working = try finalEncoding(of: working, allowUTF8Promotion: !changesCharacterSet(sets: sets, deletes: deletes, source: sourceDataSet, copyTags: copyTags))
            if !dryRun { dataSet = working }
            return lines
        } catch {
            return ["EDIT (refused: \(error.localizedDescription))"]
        }
    }

    /// Apply an edit transactionally. Dry runs execute the same validation and
    /// encoding path, but only a successful non-dry run replaces the caller's dataset.
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
        var working = try normalizedDestination(dataSet)
        let source = try normalizedCopySource(sourceDataSet)
        let lines = try apply(to: &working, sets: sets, deletes: deletes, deletePrivate: deletePrivate,
                              sourceDataSet: source, copyTags: copyTags, verbose: verbose, strict: true)
        working = try finalEncoding(of: working, allowUTF8Promotion: !changesCharacterSet(sets: sets, deletes: deletes, source: sourceDataSet, copyTags: copyTags))
        if !dryRun { dataSet = working }
        return lines
    }

    private func normalizedCopySource(_ source: DataSet?) throws -> DataSet? {
        guard let source else { return nil }
        var normalized = try source.transcodingText()
        // A selector for Specific Character Set refers to the source declaration,
        // not the temporary encoding used while preparing the transaction.
        if let declaration = source[.specificCharacterSet] { normalized[.specificCharacterSet] = declaration }
        else { normalized.remove(tag: .specificCharacterSet) }
        return normalized
    }

    private func normalizedDestination(_ source: DataSet) throws -> DataSet {
        var normalized = try source.transcodingText()
        if let declaration = source[.specificCharacterSet] { normalized[.specificCharacterSet] = declaration }
        else { normalized.remove(tag: .specificCharacterSet) }
        return normalized
    }

    private func changesCharacterSet(sets: [String], deletes: [String], source: DataSet?, copyTags: [String]) -> Bool {
        if deletes.contains(where: { parseTagSpecifier($0) == .specificCharacterSet }) { return true }
        if sets.contains(where: { spec in
            guard let equals = spec.firstIndex(of: "=") else { return false }
            return parseTagSpecifier(String(spec[..<equals])) == .specificCharacterSet
        }) { return true }
        guard let source else { return false }
        return copyTags.isEmpty ? source[.specificCharacterSet] != nil
            : copyTags.contains(where: { parseTagSpecifier($0) == .specificCharacterSet })
    }

    private func finalEncoding(of working: DataSet, allowUTF8Promotion: Bool) throws -> DataSet {
        let declared = working[.specificCharacterSet]?.stringValue
        do {
            var encoded = try working.transcodingText(to: declared ?? "", preservingItemOverrides: true)
            if declared == nil { encoded.remove(tag: .specificCharacterSet) }
            return encoded
        } catch {
            guard allowUTF8Promotion else { throw error }
            // Preserve a compatible original encoding. New text outside its repertoire
            // requires an actual UTF-8 transcode and declaration, never a byte relabel.
            return try working.transcodingText(to: "ISO_IR 192", preservingItemOverrides: true)
        }
    }

    private func apply(
        to dataSet: inout DataSet,
        sets: [String],
        deletes: [String],
        deletePrivate: Bool,
        sourceDataSet: DataSet?,
        copyTags: [String],
        verbose: Bool,
        strict: Bool
    ) throws -> [String] {
        var descriptions: [String] = []
        if strict {
            for spec in deletes + copyTags {
                guard let tag = parseTagSpecifier(spec) else { throw TagEditRefusal("Unknown or malformed tag: \(specifierDescription(spec))") }
                if let reason = TagEditRules.dataSetRefusal(for: tag) { throw TagEditRefusal(reason) }
            }
            for spec in sets {
                guard let equals = spec.firstIndex(of: "="), let tag = parseTagSpecifier(String(spec[..<equals])) else {
                    throw TagEditRefusal("Invalid --set \(specifierDescription(spec)); expected a known TagName=Value or numeric tag")
                }
                if let reason = TagEditRules.dataSetRefusal(for: tag) { throw TagEditRefusal(reason) }
            }
            if !copyTags.isEmpty, sourceDataSet == nil { throw TagEditRefusal("Copy selectors require a source dataset") }
        }
        for spec in deletes {
            guard let tag = parseTagSpecifier(spec) else { descriptions.append("DELETE \(spec) (unknown tag, skipped)"); continue }
            let label = label(for: tag)
            if tag == .sopClassUID || tag == .sopInstanceUID {
                let refusal = TagEditRefusal("DELETE \(label): a SOP identity cannot be removed by a tag edit")
                if strict { throw refusal }
                descriptions.append("DELETE \(label) (refused: \(refusal.message))")
            } else if let reason = TagEditRules.dataSetRefusal(for: tag) { descriptions.append("DELETE \(label) (refused: \(reason))") }
            else if dataSet[tag] != nil { dataSet.remove(tag: tag); descriptions.append("DELETE \(label)") }
            else { descriptions.append("DELETE \(label) (not present, skipped)") }
        }
        if deletePrivate {
            let tags = dataSet.tags.filter(\.isOddGroup)
            for tag in tags {
                dataSet.remove(tag: tag)
                if verbose { descriptions.append("DELETE private tag \(label(for: tag))") }
            }
            if !verbose { descriptions.append("DELETE \(tags.count) private tag(s)") }
        }
        if let source = sourceDataSet {
            let tags = copyTags.isEmpty ? source.tags : copyTags.compactMap { parseTagSpecifier($0) }
            for tag in tags {
                guard let element = source[tag] else {
                    if strict { throw TagEditRefusal("COPY \(label(for: tag)): selected tag is absent from the source") }
                    descriptions.append("COPY \(label(for: tag)) (not present, skipped)"); continue
                }
                if let reason = TagEditRules.dataSetRefusal(for: tag) {
                    if strict { throw TagEditRefusal(reason) }
                    descriptions.append("COPY \(label(for: tag)) (refused: \(reason))"); continue
                }
                if tag == .sopClassUID || tag == .sopInstanceUID {
                    let values = DICOMValueRules.values(of: element)
                    guard element.vr == .UI, values.count == 1, let value = values.first,
                          DICOMValueRules.isValidUID(value) else {
                        let refusal = TagEditRefusal("COPY \(label(for: tag)): a SOP identity must contain one valid non-empty UID")
                        if strict { throw refusal }
                        descriptions.append("COPY \(label(for: tag)) (refused: \(refusal.message))"); continue
                    }
                }
                dataSet[tag] = element
                descriptions.append("COPY \(label(for: tag)) = \(element.stringValue ?? "<binary>")")
            }
        }
        // Resolve every US/SS value using the final Pixel Representation, including
        // a value set later in the same command. This also applies to dry runs.
        var context = dataSet
        for spec in sets {
            guard let equals = spec.firstIndex(of: "="),
                  let tag = parseTagSpecifier(String(spec[..<equals])), tag == .pixelRepresentation else { continue }
            let value = String(spec[spec.index(after: equals)...])
            switch TagEditRules.element(tag: tag, vr: .US, text: value) {
            case .success(let element): context[tag] = element
            case .failure(let refusal): if strict { throw refusal }
            }
        }
        for spec in sets {
            guard let equals = spec.firstIndex(of: "=") else {
                descriptions.append("SET \(spec) (invalid format, expected TagName=Value)"); continue
            }
            let tagText = String(spec[..<equals]), value = String(spec[spec.index(after: equals)...])
            guard let tag = parseTagSpecifier(tagText) else { descriptions.append("SET \(tagText) (unknown tag, skipped)"); continue }
            let label = label(for: tag)
            do {
                if let reason = TagEditRules.dataSetRefusal(for: tag) { throw TagEditRefusal(reason) }
                let vr = try TagEditRules.resolvedWriteVR(for: tag, existing: dataSet[tag]?.vr, in: context)
                let element = try TagEditRules.element(tag: tag, vr: vr, text: value).get()
                dataSet[tag] = element
                descriptions.append("SET \(label) = \(value)")
            } catch {
                if strict { throw error }
                descriptions.append("SET \(label) (refused: \(error.localizedDescription))")
            }
        }
        return descriptions
    }

    private func specifierDescription(_ text: String) -> String { String(reflecting: text) }

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
