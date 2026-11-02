import Foundation
import DICOMCore
import DICOMDictionary

/// Matching expressions are distinct from stored scalar values (PS3.18 8.3.4.1).
enum QIDOQueryRules {
    static func canonicalPath(_ path: String) throws -> String {
        let parts = path.components(separatedBy: ".")
        guard !parts.isEmpty else { throw refusal("Empty attribute path") }
        var tags: [String] = []
        for (index, part) in parts.enumerated() {
            let tag: Tag
            if part.utf8.count == 8, part.utf8.allSatisfy({ (48...57).contains($0) || (65...70).contains($0) || (97...102).contains($0) }),
               let number = UInt32(part, radix: 16) {
                tag = Tag(group: UInt16(number >> 16), element: UInt16(number & 0xFFFF))
            } else if let entry = DataElementDictionary.lookup(keyword: part) {
                tag = entry.tag
            } else { throw refusal("Unknown attribute path: \(path)") }
            if index < parts.count - 1, DataElementDictionary.lookup(tag: tag)?.vr.contains(.SQ) != true {
                throw refusal("Non-sequence component in attribute path: \(path)")
            }
            tags.append(String(format: "%04X%04X", tag.group, tag.element))
        }
        return tags.joined(separator: ".")
    }

    static func tag(_ hex: String) -> Tag {
        let value = UInt32(hex, radix: 16)!
        return Tag(group: UInt16(value >> 16), element: UInt16(value & 0xFFFF))
    }

    static func nonnegativeInteger(_ text: String, name: String) throws -> Int {
        guard !text.isEmpty, text.utf8.allSatisfy({ (48...57).contains($0) }), let value = Int(text) else {
            throw refusal("\(name) must be a non-negative integer within the supported integer range")
        }
        return value
    }

    static func validate(_ expression: String, path: String) throws {
        guard !expression.isEmpty else { return } // Universal matching, not an absent predicate.
        let leaf = tag(String(path.split(separator: ".").last!))
        guard let vr = DataElementDictionary.lookup(tag: leaf)?.vr.first else { throw refusal("Unsupported matching attribute: \(path)") }
        let valid: Bool
        switch vr {
        case .UI:
            valid = expression.components(separatedBy: ",").allSatisfy(DICOMValueRules.isValidUID)
        case .DA, .TM:
            valid = range(expression, vr: vr) != nil
        case .CS:
            // A query CS can contain wildcard characters, but a comma or value
            // delimiter does not introduce UID-list matching for this VR.
            valid = expression.unicodeScalars.allSatisfy { (65...90).contains($0.value) || (48...57).contains($0.value) || [32, 95, 42, 63].contains($0.value) }
        case .IS:
            valid = DICOMValueRules.valueProblem(expression, vr: .IS) == nil
        case .US:
            valid = UInt16(expression) != nil
        case .SQ:
            valid = false // Named child paths express sequence matching.
        default:
            valid = !expression.unicodeScalars.contains { $0.value < 0x20 || (0x7F...0x9F).contains($0.value) }
        }
        if !valid { throw refusal("Invalid matching expression for \(path) (\(vr)): \(String(reflecting: expression))") }
    }

    /// AND across scalar predicates, and AND within one matching item of each sequence.
    static func matches(_ attributes: [Tag: DataElement], predicates: [String: String], fuzzy: Bool) -> Bool {
        var combinedKeys: Set<String> = []
        for (dateKey, timeKey) in [("00080020", "00080030"), ("00400244", "00400245")] {
            guard let date = predicates[dateKey], let time = predicates[timeKey],
                  let combined = combinedRange(date: date, time: time) else { continue }
            guard let dateValues = attributes[tag(dateKey)]?.stringValues,
                  let timeValues = attributes[tag(timeKey)]?.stringValues,
                  dateValues.contains(where: { dateValue in
                      timeValues.contains { timeValue in
                          guard let day = range(dateValue, vr: .DA), let clock = range(timeValue, vr: .TM) else { return false }
                          let lower = day.lowerBound + clock.lowerBound
                          let upper = day.upperBound + clock.upperBound
                          return lower <= combined.upperBound && combined.lowerBound <= upper
                      }
                  }) else { return false }
            combinedKeys.formUnion([dateKey, timeKey])
        }
        var nested: [String: [String: String]] = [:]
        for (path, expression) in predicates where !expression.isEmpty && !combinedKeys.contains(path) {
            let parts = path.split(separator: ".", maxSplits: 1).map(String.init)
            if parts.count == 2 { nested[parts[0], default: [:]][parts[1]] = expression }
            else {
                guard let element = attributes[tag(parts[0])], matches(element, expression: expression, fuzzy: fuzzy) else { return false }
            }
        }
        for (head, children) in nested {
            guard let items = attributes[tag(head)]?.sequenceItems,
                  items.contains(where: { matches($0.elements, predicates: children, fuzzy: fuzzy) }) else { return false }
        }
        return true
    }

    static func matches(_ element: DataElement, expression: String, fuzzy: Bool) -> Bool {
        let values = element.stringValues ?? element.uint16Values?.map(String.init) ?? []
        switch element.vr {
        case .UI:
            let wanted = Set(expression.components(separatedBy: ","))
            return values.contains(where: wanted.contains)
        case .DA, .TM:
            guard let query = range(expression, vr: element.vr) else { return false }
            return values.contains { value in
                guard let stored = range(value, vr: element.vr) else { return false }
                return stored.lowerBound <= query.upperBound && query.lowerBound <= stored.upperBound
            }
        case .IS:
            guard let wanted = Int(expression.trimmingCharacters(in: .whitespaces)) else { return false }
            return values.contains { Int($0.trimmingCharacters(in: .whitespaces)) == wanted }
        case .US:
            guard let wanted = UInt16(expression) else { return false }
            return element.uint16Values?.contains(wanted) == true
        default:
            return values.contains { wildcard($0, pattern: expression, fuzzy: fuzzy && element.vr == .PN) }
        }
    }

    static func wildcard(_ value: String, pattern: String, fuzzy: Bool = false) -> Bool {
        if fuzzy {
            return value.localizedCaseInsensitiveContains(pattern.replacingOccurrences(of: "*", with: "").replacingOccurrences(of: "?", with: ""))
        }
        let expression = NSRegularExpression.escapedPattern(for: pattern)
            .replacingOccurrences(of: "\\*", with: ".*").replacingOccurrences(of: "\\?", with: ".")
        return value.range(of: "\\A(?:" + expression + ")\\z", options: .regularExpression) != nil
    }

    /// PS3.4 C.2.2.2.5.4: concatenate corresponding bounds only when both
    /// values specify the same range form. A middle day is not time-filtered.
    private static func combinedRange(date: String, time: String) -> ClosedRange<Int64>? {
        let dates = date.components(separatedBy: "-")
        let times = time.components(separatedBy: "-")
        guard dates.count == 2, times.count == 2,
              dates[0].isEmpty == times[0].isEmpty, dates[1].isEmpty == times[1].isEmpty,
              let days = range(date, vr: .DA), let clocks = range(time, vr: .TM) else { return nil }
        let lower = days.lowerBound == .min ? Int64.min : days.lowerBound + clocks.lowerBound
        let upper = days.upperBound == .max ? Int64.max : days.upperBound + clocks.upperBound
        return lower <= upper ? lower...upper : nil
    }

    private static func range(_ text: String, vr: VR) -> ClosedRange<Int64>? {
        func interval(_ value: String) -> ClosedRange<Int64>? {
            if vr == .DA {
                guard DICOMValueRules.isValidDate(value), let date = DICOMDate.parse(value)?.toDate() else { return nil }
                let day = Int64(date.timeIntervalSince1970) * 1_000_000
                return day...day
            }
            guard DICOMValueRules.isValidTime(value) else { return nil }
            let value = value.trimmingCharacters(in: CharacterSet(charactersIn: " "))
            let main = value.components(separatedBy: ".")[0]
            let bytes = Array(main.utf8)
            func number(_ start: Int) -> Int { Int(bytes[start] - 48) * 10 + Int(bytes[start + 1] - 48) }
            let lower = Int64(number(0) * 3600 + (bytes.count >= 4 ? number(2) * 60 : 0) + (bytes.count >= 6 ? number(4) : 0)) * 1_000_000
            if value.contains(".") {
                let digits = value.components(separatedBy: ".")[1]
                let fraction = Int64(digits + String(repeating: "0", count: 6 - digits.count))!
                var width: Int64 = 1
                for _ in digits.count..<6 { width *= 10 }
                return (lower + fraction)...(lower + fraction + width - 1)
            }
            let width: Int64 = bytes.count == 2 ? 3_600_000_000 : bytes.count == 4 ? 60_000_000 : 1_000_000
            return lower...(lower + width - 1)
        }
        let parts = text.components(separatedBy: "-")
        if parts.count == 1 { return interval(text) }
        guard parts.count == 2, !parts.allSatisfy(\.isEmpty),
              parts[0].isEmpty || interval(parts[0]) != nil, parts[1].isEmpty || interval(parts[1]) != nil else { return nil }
        let lower = parts[0].isEmpty ? Int64.min : interval(parts[0])!.lowerBound
        let upper = parts[1].isEmpty ? Int64.max : interval(parts[1])!.upperBound
        return lower <= upper ? lower...upper : nil
    }

    static func refusal(_ message: String) -> DICOMwebError { .badRequest(message: message) }
}
