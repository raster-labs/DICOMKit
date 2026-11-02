import Foundation

/// The implemented resource tree, shared by WADL XML, its Annex G JSON
/// encoding, and method discovery. PS3.18 2026a 8.9 and Annex H.
enum DICOMwebCapabilitiesDescription {
    static let namespace = "http://wadl.dev.java.net/2009/02"
    static let json = "application/json"
    static let xml = "application/vnd.sun.wadl+xml"
    static let multipart = "multipart/related; type=\"application/dicom\""
    static let dicomJSON = "application/dicom+json"
    static let textDescription = "Text representations use UTF-8. Stored application/dicom instances are returned without transcoding. Frames, rendered images, thumbnails, bulk data and UPS event subscriptions are unavailable. DELETE on Studies resources and GET capabilities are DICOMKit extensions."

    struct Method {
        let name: String
        let responseTypes: [String]
        let requestTypes: [String]
        let status: String
        init(_ name: String, _ responseTypes: [String] = [], request: [String] = [], status: String = "200") {
            self.name = name; self.responseTypes = responseTypes; self.requestTypes = request; self.status = status
        }
        var object: [String: Any] {
            var result: [String: Any] = ["@name": name,
                "response": [["@status": status, "representation": responseTypes.map { ["@mediaType": $0] }]]]
            var request: [String: Any] = [:]
            if !responseTypes.isEmpty { request["param"] = [["@name": "Accept", "@style": "header", "@required": "true"]] }
            if !requestTypes.isEmpty { request["representation"] = requestTypes.map { ["@mediaType": $0] } }
            if !request.isEmpty { result["request"] = request }
            return result
        }
    }
    struct Resource {
        let path: String
        var methods: [Method] = []
        var children: [Resource] = []
        var object: [String: Any] {
            var result: [String: Any] = ["@path": path]
            if path.hasPrefix("{"), path.hasSuffix("}") {
                result["param"] = [["@name": String(path.dropFirst().dropLast()), "@style": "template", "@required": "true"]]
            }
            if !methods.isEmpty { result["method"] = methods.map(\.object) }
            if !children.isEmpty { result["resource"] = children.map(\.object) }
            return result
        }
    }

    static func tree(upsEnabled: Bool) -> Resource {
        let search = Method("GET", [dicomJSON])
        let metadata = Resource(path: "metadata", methods: [search])
        let store = Method("POST", [dicomJSON], request: [multipart, "application/dicom"], status: "200 202")
        let deletion = Method("DELETE", status: "204")
        let instance = Resource(path: "{instanceUID}", methods: [Method("GET", [multipart, "application/dicom"]), deletion], children: [metadata])
        let series = Resource(path: "{seriesUID}", methods: [Method("GET", [multipart]), deletion], children: [metadata,
            Resource(path: "instances", methods: [search], children: [instance])])
        let study = Resource(path: "{studyUID}", methods: [Method("GET", [multipart]), store, deletion], children: [metadata,
            Resource(path: "series", methods: [search], children: [series]), Resource(path: "instances", methods: [search])])
        var root = Resource(path: "", methods: [Method("GET", [json])], children: [
            Resource(path: "capabilities", methods: [Method("GET", [json])]),
            Resource(path: "studies", methods: [search, store], children: [study]),
            Resource(path: "series", methods: [search]), Resource(path: "instances", methods: [search])])
        if upsEnabled {
            let cancel = Resource(path: "cancelrequest", methods: [Method("POST", request: [dicomJSON], status: "202"),
                                                                  Method("PUT", request: [dicomJSON], status: "202")])
            let workitem = Resource(path: "{workitemUID}", methods: [search, Method("POST", request: [dicomJSON]), Method("PUT", request: [dicomJSON])],
                                    children: [Resource(path: "state", methods: [Method("PUT", request: [dicomJSON])]), cancel])
            root.children.append(Resource(path: "workitems", methods: [search, Method("POST", request: [dicomJSON], status: "201")], children: [workitem]))
        }
        return root
    }

    static func object(baseURL: URL, upsEnabled: Bool) -> [String: Any] {
        // resources is repeatable in WADL; Annex H restricts it to one entry.
        ["application": ["@xmlns": namespace, "doc": [["@xml:lang": "en", "value": textDescription]],
            "resources": [["@base": baseURL.absoluteString, "resource": [tree(upsEnabled: upsEnabled).object]]]]]
    }

    static func data(baseURL: URL, upsEnabled: Bool, mediaType: String) throws -> Data {
        let object = object(baseURL: baseURL, upsEnabled: upsEnabled)
        if mediaType == json { return try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]) }
        return Data(("<?xml version=\"1.0\" encoding=\"UTF-8\"?>" + element("application", object["application"] as! [String: Any])).utf8)
    }

    private static func escape(_ value: String) -> String {
        value.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
    }

    private static func element(_ name: String, _ object: [String: Any]) -> String {
        let attributes = object.keys.filter { $0.hasPrefix("@") }.sorted()
            .map { " \($0.dropFirst())=\"\(escape(object[$0] as! String))\"" }.joined()
        // WADL schema ordering: documentation, parameters, methods/resources;
        // within methods: request before response.
        let order = ["doc", "resources", "param", "request", "representation", "response", "method", "resource"]
        var body = (object["value"] as? String).map(escape) ?? ""
        for key in order {
            if let values = object[key] as? [[String: Any]] { body += values.map { element(key, $0) }.joined() }
            else if let value = object[key] as? [String: Any] { body += element(key, value) }
        }
        return "<\(name)\(attributes)>\(body)</\(name)>"
    }

    /// Returns methods for an implemented resource, excluding unsupported route stubs.
    static func methods(relativePath: String, upsEnabled: Bool) -> [String]? {
        let parts = relativePath.split(separator: "/").map(String.init)
        func find(_ resource: Resource, _ remaining: ArraySlice<String>) -> Resource? {
            guard let head = remaining.first else { return resource }
            guard let child = resource.children.first(where: { $0.path == head })
                ?? resource.children.first(where: { $0.path.hasPrefix("{") }) else { return nil }
            return find(child, remaining.dropFirst())
        }
        guard let resource = find(tree(upsEnabled: upsEnabled), parts[...]) else { return nil }
        return resource.methods.map(\.name) + (parts.isEmpty ? ["OPTIONS"] : [])
    }

    /// 8.7.5/8.7.7: unsupported ranges are ignored; q=0 excludes a selected
    /// representation even when a less-specific wildcard would allow it.
    static func selectedMediaType(_ request: DICOMwebRequest) -> String? {
        guard let header = request.header("Accept"), !header.isEmpty else { return nil }
        func quality(_ value: String?) -> Double? {
            guard let value else { return 1 }
            guard value.range(of: #"\A(?:0(?:\.[0-9]{0,3})?|1(?:\.0{0,3})?)\z"#, options: .regularExpression) != nil else { return nil }
            return Double(value)
        }
        func charsetAllowed() -> Bool {
            guard let header = request.header("Accept-Charset") else { return true }
            var exact: Double?, wildcard: Double?
            for part in header.split(separator: ",") {
                let fields = part.split(separator: ";").map { $0.trimmingCharacters(in: .whitespaces) }
                guard let first = fields.first else { continue }
                let name = first.trimmingCharacters(in: CharacterSet(charactersIn: "\" ")).lowercased()
                let q = fields.dropFirst().first { $0.lowercased().hasPrefix("q=") }.map { String($0.dropFirst(2)) }
                guard let weight = quality(q) else { continue }
                if ["utf-8", "iso_ir 192"].contains(name) { exact = max(exact ?? 0, weight) }
                if name == "*" { wildcard = max(wildcard ?? 0, weight) }
            }
            return (exact ?? wildcard ?? 0) > 0
        }
        var selected: (String, Double)?
        for candidate in [json, xml] {
            var best: (specificity: Int, quality: Double)?
            for entry in header.split(separator: ",") {
                let fields = entry.split(separator: ";", omittingEmptySubsequences: false).map { $0.trimmingCharacters(in: .whitespaces) }
                guard let first = fields.first, !first.contains(where: \.isWhitespace) else { continue }
                var names: Set<String> = []
                let valid = fields.dropFirst().allSatisfy { field in
                    let pair = field.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false).map { $0.trimmingCharacters(in: .whitespaces) }
                    guard pair.count == 2, !pair[1].isEmpty, names.insert(pair[0].lowercased()).inserted else { return false }
                    if pair[0].lowercased() == "q" { return !pair[1].hasPrefix("\"") }
                    return pair[1].hasPrefix("\"") == pair[1].hasSuffix("\"")
                }
                guard valid, let type = DICOMMediaType.parse(String(entry)), let q = quality(type.parameters["q"]),
                      Set(type.parameters.keys).isSubset(of: ["q", "charset"]) else { continue }
                if let charset = type.parameters["charset"], !["utf-8", "iso_ir 192"].contains(charset.lowercased()) { continue }
                if type.parameters["charset"] == nil && !charsetAllowed() { continue }
                let specificity: Int
                if "\(type.type)/\(type.subtype)" == candidate { specificity = 2 }
                else if type.type == "application", type.subtype == "*" { specificity = 1 }
                else if type.type == "*", type.subtype == "*" { specificity = 0 }
                else { continue }
                if best == nil || specificity > best!.specificity || (specificity == best!.specificity && q > best!.quality) { best = (specificity, q) }
            }
            if let best, best.quality > 0, best.quality > (selected?.1 ?? 0) { selected = (candidate, best.quality) }
        }
        return selected?.0
    }
}
