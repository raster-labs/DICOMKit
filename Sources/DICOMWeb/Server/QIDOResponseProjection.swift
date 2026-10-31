import Foundation
import DICOMCore
import DICOMDictionary

/// Supported response fields and defaults from PS3.18 2026a 10.6.3.3.
/// This bounded projection never returns child-entity attributes for a parent search.
enum QIDOResponseProjection {
    private static let study = Set(["00080020", "00080030", "00080050", "00080056", "00080061", "00080090", "00080201",
                                    "00081190", "00100010", "00100020", "00100030", "00100040", "0020000D", "00200010", "00201206", "00201208"])
    private static let series = Set(["00080060", "00080201", "0008103E", "00081190", "0020000E", "00200011", "00201209",
                                     "00400244", "00400245", "00400275.00400009", "00400275.00401001"])
    private static let instance = Set(["00080016", "00080018", "00080056", "00080201", "00081190", "00200013", "00280010", "00280011", "00280100", "00280008"])
    private static let requiredStudy = Set(["00080020", "00080030", "00080050", "00080061", "00080090", "00100010", "00100020", "00100030", "00100040", "0020000D", "00200010", "00201206", "00201208"])
    private static let requiredSeries = Set(["00080060", "00081190", "0020000E", "00200011", "00201209"])

    static func entityLevel(_ path: String) -> QIDOAttributeLevel? {
        let root = String(path.split(separator: ".")[0])
        if root == "00400275" { return .series }
        if let level = QIDOResource.matchingLevel(for: root) { return level }
        if root.hasPrefix("0010") { return .patient }
        switch root {
        case "00201206", "00201208", "00080062": return .study
        case "00201209", "00080070", "00080080", "00081090", "00181030", "00080021", "00080031", "00081050": return .series
        case "00280100", "00083002": return .instance
        default: return nil
        }
    }

    private static func permitted(_ path: String, resource: QIDOResource, all: Bool) -> Bool {
        let root = String(path.split(separator: ".")[0])
        let tag = QIDOQueryRules.tag(root)
        if tag.isPrivate { return !all }
        guard let level = entityLevel(path) else { return false }
        switch resource {
        case .allStudies: return level == .patient || level == .study
        case .studySeries, .allSeries:
            return all ? level == .series : level != .instance
        case .studyInstances, .studySeriesInstances, .allInstances:
            return all ? level == .instance : true
        }
    }

    static func project(base: [String: Any], attributes: [DataElement], query: StorageQuery, resource: QIDOResource) throws -> [String: Any] {
        var available = try DICOMJSONEncoder().encodeToObject(attributes)
        // Prefer typed metadata encoding (notably PN groups); server-generated values
        // and retrieval URLs remain authoritative.
        let generated: Set<String> = ["00081190", "0020000D", "0020000E", "00080018", "00201206", "00201208", "00201209", "00080061"]
        for (key, value) in base where available[key] == nil || generated.contains(key) { available[key] = value }
        var wanted: Set<String>
        var required: Set<String> = []
        switch resource {
        case .allStudies: wanted = study; required = requiredStudy
        case .studySeries: wanted = series.union(["0020000D"]); required = requiredSeries
        case .allSeries: wanted = series.union(study); required = requiredSeries.union(requiredStudy)
        case .studySeriesInstances: wanted = instance.union(["0020000D", "0020000E"])
        case .studyInstances: wanted = instance.union(series).union(["0020000D"]); required = requiredSeries
        case .allInstances: wanted = instance.union(series).union(study); required = requiredSeries.union(requiredStudy)
        }
        for path in query.includeFields + Array(query.matchingAttributes.keys) where permitted(path, resource: resource, all: false) { wanted.insert(path) }
        if query.includeAll {
            for key in available.keys where permitted(key, resource: resource, all: true) { wanted.insert(key) }
        }
        for path in Array(wanted) {
            let root = String(path.split(separator: ".")[0]), tag = QIDOQueryRules.tag(root)
            if tag.isPrivate, tag.element >= 0x1000 {
                wanted.insert(String(format: "%04X%04X", tag.group, tag.element >> 8))
            }
        }
        var result = select(available, paths: wanted)
        // The two Request Attributes Sequence children are Type R whenever
        // the conditional sequence is present (PS3.18 Table 10.6.3-4).
        if var sequence = result["00400275"] as? [String: Any], let items = sequence["Value"] as? [[String: Any]] {
            sequence["Value"] = items.map { item in
                var item = item
                for key in ["00400009", "00401001"] where item[key] == nil { item[key] = ["vr": "SH"] }
                return item
            }
            result["00400275"] = sequence
        }
        for key in required where result[key] == nil {
            if let vr = DataElementDictionary.lookup(tag: QIDOQueryRules.tag(key))?.vr.first { result[key] = ["vr": vr.rawValue] }
        }
        return result
    }

    private static func select(_ available: [String: Any], paths: Set<String>) -> [String: Any] {
        var result: [String: Any] = [:]
        var nested: [String: Set<String>] = [:]
        var selectedPaths = paths
        // Apply at every Item depth, not only to top-level private attributes.
        for path in paths {
            let root = String(path.split(separator: ".")[0]), tag = QIDOQueryRules.tag(root)
            if tag.isPrivate, tag.element >= 0x1000 {
                selectedPaths.insert(String(format: "%04X%04X", tag.group, tag.element >> 8))
            }
        }
        for path in selectedPaths {
            let parts = path.split(separator: ".", maxSplits: 1).map(String.init)
            if parts.count == 1 { if let value = available[parts[0]] { result[parts[0]] = value } }
            else { nested[parts[0], default: []].insert(parts[1]) }
        }
        for (root, children) in nested where result[root] == nil {
            guard let attribute = available[root] as? [String: Any], attribute["vr"] as? String == "SQ" else { continue }
            var selected = attribute
            if let items = attribute["Value"] as? [[String: Any]] { selected["Value"] = items.map { select($0, paths: children) } }
            result[root] = selected
        }
        return result
    }
}
