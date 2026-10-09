// NEMA-verified: 2026a, checked 2026-10-01 — per-profile image attribute values of PS3.11 2026a Tables A.3-3, B.3-3, B.3-4, E.3-3 to E.3-6, K.3-3, L.4-1 (Value text parsed), the specialized Types of K.3-4 / L.4-2, the Photometric Interpretation / Transfer Syntax pairs of C.3-2, each applied to the instances its section names (A.3.4.1, B.3.4.1, C.3.1.1, E.3.4.1, K.3.4.1-2, L.4.5); the "Multi-frame Composite IODs" rows of D.3-1 / H.3-1 / I.3-1 / J.3-1 / M.3-1 / N.3-1 admit only instances with Number of Frames (0028,0008) (D233)
import Foundation
import DICOMCore

extension DICOMDIRProfileRules {

    /// A parsed Value cell of a PS3.11 "Required Image Attribute Values" table.
    enum ValueRule: Equatable {
        /// One of these values (numbers compared numerically, text exactly).
        case oneOf([String])
        /// Integers in these closed ranges.
        case integers([ClosedRange<Int>])
        /// At most this value ("up to 1024", "512 (see below)": "shall not exceed").
        case atMost(Int)
        /// Equal to another attribute plus an offset ("Bits Stored (0028,0101) - 1").
        case relative(Tag, offset: Int)
        /// "If Bits Stored (0028,0101) is 8, then 8; otherwise 16."
        case ifEquals(Tag, Int, then: Int, otherwise: Int)
    }

    /// Parses a Value cell; nil for text this parser does not know (a test keeps every
    /// generated cell parseable).
    static func parseValueRule(_ text: String) -> ValueRule? {
        let t = text.trimmingCharacters(in: .whitespaces)
        func tag(_ g: Substring, _ e: Substring) -> Tag? {
            guard let gg = UInt16(g, radix: 16), let ee = UInt16(e, radix: 16) else { return nil }
            return Tag(group: gg, element: ee)
        }
        if let m = t.firstMatch(of: #/^If [A-Za-z ']+ \(([0-9A-F]{4}),([0-9A-F]{4})\) is (\d+), then (\d+); otherwise (\d+)\.?$/#),
           let ref = tag(m.1, m.2), let v = Int(m.3), let a = Int(m.4), let b = Int(m.5) {
            return .ifEquals(ref, v, then: a, otherwise: b)
        }
        if let m = t.firstMatch(of: #/^[A-Za-z ']+ \(([0-9A-F]{4}),([0-9A-F]{4})\)(?: - (\d+))?$/#), let ref = tag(m.1, m.2) {
            return .relative(ref, offset: -(m.3.flatMap { Int($0) } ?? 0))
        }
        if let m = t.firstMatch(of: #/^(?:up to )?(\d+)(?: \(see below\))$/#), let n = Int(m.1) {
            return .atMost(n)
        }
        if let m = t.firstMatch(of: #/^([0-9A-F]{4})H \([a-z]+\)$/#), let n = Int(m.1, radix: 16) {
            return .integers([n...n])
        }
        // "8", "8 bits only", "8 or 16", "8, 10, and 12 bits only", "8, 12 to 16", "8, 10, 12 or 16"
        let numeric = t.replacingOccurrences(of: " bits only", with: "")
        if numeric.first?.isNumber == true {
            var ranges: [ClosedRange<Int>] = []
            let parts = numeric.replacingOccurrences(of: ", and ", with: ",").replacingOccurrences(of: " or ", with: ",")
                .split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            for part in parts {
                let bounds = part.components(separatedBy: " to ")
                guard let lo = Int(bounds[0]), let hi = Int(bounds.last ?? ""), bounds.count <= 2 else { return nil }
                ranges.append(lo...hi)
            }
            return ranges.isEmpty ? nil : .integers(ranges)
        }
        if t.allSatisfy({ $0.isUppercase || $0.isNumber || $0 == " " || $0 == "_" }) { return .oneOf([t]) }
        return nil
    }

    /// The PS3.11 image attribute tables that apply to an instance of `sopClassUID` with
    /// Photometric Interpretation `photometric` under `profile` (the files each section names).
    static func imageAttributeTables(sopClassUID: String, photometric: String?, profileID id: String) -> [String] {
        let xa = "1.2.840.10008.5.1.4.1.1.12.1"          // X-Ray Angiographic Image Storage
        let sc = "1.2.840.10008.5.1.4.1.1.7"             // Secondary Capture Image Storage
        let ct = "1.2.840.10008.5.1.4.1.1.2"             // CT Image Storage
        let mr = "1.2.840.10008.5.1.4.1.1.4"             // MR Image Storage
        let dental: Set<String> = [                       // Digital Intra-Oral X-Ray, Digital X-Ray
            "1.2.840.10008.5.1.4.1.1.1.3", "1.2.840.10008.5.1.4.1.1.1.3.1",
            "1.2.840.10008.5.1.4.1.1.1.1", "1.2.840.10008.5.1.4.1.1.1.1.1",
        ]
        switch id {
        case "STD-XABC-CD":                               // A.3.4.1: "X-Ray Angiographic Image files"
            return sopClassUID == xa ? ["A.3-3"] : []
        case "STD-XA1K-CD", "STD-XA1K-DVD":               // B.3.4.1: XA Image files, SC Image files
            return sopClassUID == xa ? ["B.3-3"] : sopClassUID == sc ? ["B.3-4"] : []
        case "STD-DEN-CD":                                // K.3.4.1 / K.3.4.2: "the image files"
            return isMediaStorageSOPClass(sopClassUID) ? ["K.3-3", "K.3-4"] : []
        case "STD-DTL-SEC-ZIP-MAIL":                      // L.4.5: Intra-oral and DX instances
            return dental.contains(sopClassUID) ? ["L.4-1", "L.4-2"] : []
        default:
            break
        }
        if id.hasPrefix("STD-CTMR-") {                    // E.3.4.1: CT, MR, grayscale / color SC
            if sopClassUID == ct { return ["E.3-3"] }
            if sopClassUID == mr { return ["E.3-4"] }
            if sopClassUID == sc {
                return (photometric ?? "").hasPrefix("MONOCHROME") ? ["E.3-5"] : ["E.3-6"]
            }
        }
        return []
    }

    /// What breaks the PS3.11 2026a image attribute values, specialized Types and (STD-US)
    /// Photometric Interpretation / Transfer Syntax pairs of `profile`; empty when nothing does.
    public static func imageAttributeProblems(in dataSet: DataSet, sopClassUID: String,
                                              transferSyntaxUID: String, profile: DICOMDIRProfile) -> [String] {
        guard profile.isStandard else { return [] }
        let id = profile.rawValue
        var problems: [String] = []
        func text(_ tag: Tag) -> String? {
            dataSet.string(for: tag)?.trimmingCharacters(in: CharacterSet(charactersIn: " \0"))
        }
        func integer(_ tag: Tag) -> Int? {
            if let v = dataSet.uint16(for: tag) { return Int(v) }
            return text(tag).flatMap { Int($0) }
        }
        let photometric = text(.photometricInterpretation)

        if id.hasPrefix("STD-US-"), dataSet[.pixelData] != nil, let pi = photometric {
            // C.3.1.1, Table C.3-2
            let allowed = ultrasoundPhotometricTransferSyntaxes[pi] ?? []
            if !allowed.contains(transferSyntaxUID) {
                problems.append("Photometric Interpretation \(pi) with Transfer Syntax \(named(transferSyntaxUID)) is not a pair of Table C.3-2")
            }
        }

        for label in imageAttributeTables(sopClassUID: sopClassUID, photometric: photometric, profileID: id) {
            for row in imageAttributeValueTables[label] ?? [] {
                guard let rule = parseValueRule(row.value) else { continue }
                let where_ = "\(row.name) \(row.tag) [Table \(label)]"
                switch rule {
                case .oneOf(let values):
                    let value = text(row.tag) ?? ""
                    if !values.contains(value) {
                        problems.append("\(where_) is '\(value)', shall be \(row.value)")
                    }
                case .integers(let ranges):
                    guard let value = integer(row.tag) else {
                        problems.append("\(where_) is absent, shall be \(row.value)"); continue
                    }
                    if !ranges.contains(where: { $0.contains(value) }) {
                        problems.append("\(where_) is \(value), shall be \(row.value)")
                    }
                case .atMost(let limit):
                    if let value = integer(row.tag), value > limit {
                        problems.append("\(where_) is \(value), shall not exceed \(limit)")
                    }
                case .relative(let ref, let offset):
                    if let value = integer(row.tag), let base = integer(ref), value != base + offset {
                        problems.append("\(where_) is \(value), shall be \(row.value) = \(base + offset)")
                    }
                case .ifEquals(let ref, let when, let then, let otherwise):
                    if let value = integer(row.tag), let base = integer(ref) {
                        let expected = base == when ? then : otherwise
                        if value != expected { problems.append("\(where_) is \(value), shall be \(expected) (\(row.value))") }
                    }
                }
            }
            for row in imageAttributeTypeTables[label] ?? [] where row.type == "2" && dataSet[row.tag] == nil {
                problems.append("\(row.name) \(row.tag) is absent; the profile makes it Type 2 [Table \(label)]")
            }
        }
        return problems
    }
}
