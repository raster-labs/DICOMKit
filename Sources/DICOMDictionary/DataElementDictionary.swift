import Foundation
import DICOMCore

enum DICOMDictionaryResourceBundle {
    static let bundleName = "DICOMKit_DICOMDictionary.bundle"

    static func packagedBundle(mainResourceURL: URL?) -> Bundle? {
        guard let mainResourceURL else { return nil }
        return Bundle(url: mainResourceURL.appendingPathComponent(bundleName, isDirectory: true))
    }

    static var resolved: Bundle {
        // SwiftPM's generated Bundle.module accessor looks beside Bundle.main's
        // bundle URL. A conventionally signed macOS app must instead place
        // nested resource bundles in Contents/Resources, so prefer that
        // production location and retain Bundle.module for package tools/tests.
        packagedBundle(mainResourceURL: Bundle.main.resourceURL) ?? Bundle.module
    }
}

/// Comprehensive DICOM Data Element Dictionary
///
/// Contains every data element of PS3.6 2026a Tables 6-1, 7-1, 8-1 and 9-1 and the
/// command elements of PS3.7 2026a Tables E.1-1 and E.2-1, including the repeating
/// groups (50xx Curve, 60xx Overlay) stored once at their base group.
///
/// Dictionary data is stored as a bundled resource file for zero compilation overhead.
/// `Scripts/generate_full_dictionary.py` writes it from the NEMA DocBook text; each row
/// is `GGGG|EEEE|Name|Keyword|VR[/VR...]|VM|Retired`, lines starting with `#` are
/// comments. Parsed once at first access and cached in a static dictionary.
///
/// NEMA-verified: 2026a, checked 2026-09-28 — the resource is generated row for row from
/// PS3.6 2026a Tables 6-1, 7-1, 8-1, 9-1 and PS3.7 2026a Tables E.1-1, E.2-1 (5,326 rows;
/// `Scripts/diff_dictionary.py` re-checks it); the loader keeps blank cells blank (a blank
/// VR loads as UN) and the 50xx/60xx canonicalisation follows PS3.5 §7.6 (even groups only).
public struct DataElementDictionary: Sendable {

    // MARK: - Parsed Dictionary

    private static let entries: [Tag: DataElementEntry] = {
        guard let url = DICOMDictionaryResourceBundle.resolved.url(
            forResource: "DataElementDictionary", withExtension: "txt"),
              let content = try? String(contentsOf: url, encoding: .utf8) else {
            return [:]
        }
        var dict = [Tag: DataElementEntry](minimumCapacity: 5400)
        for line in content.split(separator: "\n") {
            // Keep empty subsequences so a blank field (e.g. an empty Name)
            // doesn't collapse the column count and drop/misalign the row.
            if line.hasPrefix("#") { continue }
            let fields = line.split(separator: "|", maxSplits: 6, omittingEmptySubsequences: false)
            guard fields.count >= 6,
                  let group = UInt16(fields[0], radix: 16),
                  let element = UInt16(fields[1], radix: 16) else { continue }
            let tag = Tag(group: group, element: element)
            // Multi-VR attributes ("US/OW") keep every VR, primary first.
            let vrs = fields[4].split(separator: "/").compactMap { VR(rawValue: String($0)) }
            let retired = fields.count > 6 && fields[6] == "R"
            dict[tag] = DataElementEntry(
                tag: tag,
                name: String(fields[2]),
                keyword: String(fields[3]),
                vr: vrs.isEmpty ? [.UN] : vrs,
                vm: String(fields[5]),
                retired: retired
            )
        }
        return dict
    }()

    /// Maps a tag in a repeating group (50xx Curve, 60xx Overlay — even groups
    /// only, per PS3.5 7.6) to the base-group tag under which it is stored.
    /// Any other tag is returned unchanged.
    static func canonicalTag(_ tag: Tag) -> Tag {
        let group = tag.group
        guard group & 0x0001 == 0 else { return tag }
        switch group {
        case 0x5000...0x50FF: return Tag(group: 0x5000, element: tag.element)
        case 0x6000...0x60FF: return Tag(group: 0x6000, element: tag.element)
        default: return tag
        }
    }

    /// Looks up a data element entry by tag
    ///
    /// Repeating-group tags (e.g. Overlay Rows (6002,0010)) resolve to their
    /// base-group entry; the returned entry's `tag` is the base-group tag.
    /// - Parameter tag: The tag to look up
    /// - Returns: The dictionary entry, or nil if not found
    public static func lookup(tag: Tag) -> DataElementEntry? {
        return entries[canonicalTag(tag)]
    }

    /// Every entry, sorted by tag. Repeating-group entries appear once, at their base group.
    public static var allEntries: [DataElementEntry] {
        return entries.values.sorted { ($0.tag.group, $0.tag.element) < ($1.tag.group, $1.tag.element) }
    }

    /// Looks up a data element entry by keyword
    /// - Parameter keyword: The keyword to look up
    /// - Returns: The dictionary entry, or nil if not found
    public static func lookup(keyword: String) -> DataElementEntry? {
        // A few PS3.6 rows have no keyword; an empty string must not match them.
        guard !keyword.isEmpty else { return nil }
        return entries.values.first { $0.keyword == keyword }
    }
}
