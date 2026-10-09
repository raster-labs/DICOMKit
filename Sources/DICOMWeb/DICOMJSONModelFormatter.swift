import Foundation

// NEMA-verified: 2026a, checked 2026-10-01 — PS3.18 2026a F.2 (multiple results as one top-level array, F.2.1), F.2.2 (attribute objects in ascending lexicographic order of the tag name; Group Length (gggg,0000) not included)
/// Renders DICOM JSON Model objects (PS3.18 F.2) for console output: the `--format
/// dicom-json` of `dicom-wado query` and `dicom-wado ups`. The objects are written as
/// a single top-level array (F.2.1) with attribute objects ordered by their eight-character
/// tag name (F.2.2) and Group Length attributes removed (F.2.2), using the same writer the
/// DICOM JSON encoder uses. Values are passed through as the origin server sent them.
public enum DICOMJSONModelFormatter {

    /// The objects as a pretty-printed DICOM JSON Model array, newline-free at the end.
    public static func format(_ objects: [[String: Any]]) -> String {
        let cleaned: [Any] = objects.map { withoutGroupLength($0) }
        guard let data = try? DICOMJSONWriter(prettyPrinted: true, sortedKeys: true).data(with: cleaned),
              let text = String(data: data, encoding: .utf8) else {
            return "[]"
        }
        return text.hasSuffix("\n") ? String(text.dropLast()) : text
    }

    /// PS3.18 F.2.2: "Group Length (gggg,0000) attributes shall not be included". Applied
    /// to sequence items too.
    static func withoutGroupLength(_ object: [String: Any]) -> [String: Any] {
        var out: [String: Any] = [:]
        for (key, value) in object {
            if isGroupLengthTag(key) { continue }
            guard var attribute = value as? [String: Any] else {
                out[key] = value
                continue
            }
            if let items = attribute["Value"] as? [Any] {
                attribute["Value"] = items.map { item -> Any in
                    if let dataset = item as? [String: Any], attribute["vr"] as? String == "SQ" {
                        return withoutGroupLength(dataset)
                    }
                    return item
                }
            }
            out[key] = attribute
        }
        return out
    }

    private static func isGroupLengthTag(_ key: String) -> Bool {
        key.count == 8 && key.hasSuffix("0000") && key.allSatisfy(\.isHexDigit)
    }
}
