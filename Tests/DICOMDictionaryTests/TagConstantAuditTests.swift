import Testing
import Foundation
@testable import DICOMDictionary
@testable import DICOMCore

/// Every named `Tag` constant in DICOMCore must carry the tag PS3.6 assigns to
/// that keyword. The (0032,1070)-for-Requested-Procedure-Description bug was a
/// constant whose name was right and whose number was wrong; this suite makes
/// that class of mistake a test failure instead of a field report.
///
/// The constants are read from the `Sources/DICOMCore/Tag*.swift` files at
/// test time, so a new constant is covered the moment it is written.
@Suite("Tag constant audit")
struct TagConstantAuditTests {

    /// Identifiers that deliberately differ from the PS3.6 keyword.
    /// Mirror of ALLOWED_ALIASES in Scripts/audit_tags.py — keep both in sync.
    static let allowedAliases: [String: String] = [
        "exposureInMicroAs":              "ExposureInuAs",
        "verticesOfPolygonalShutter":     "VerticesOfThePolygonalShutter",
        "brachyApplicationSetupSequence": "ApplicationSetupSequence",
        "maxFractionalValue":             "MaximumFractionalValue",
    ]

    struct Constant {
        let file: String
        let line: Int
        let identifier: String
        let tag: DICOMCore.Tag
    }

    static func normalize(_ s: String) -> String {
        String(s.lowercased().filter { $0.isLetter || $0.isNumber })
    }

    static func tagSourceFiles() throws -> [URL] {
        let here = URL(fileURLWithPath: #filePath)
        let core = here.deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("Sources/DICOMCore")
        let names = try FileManager.default.contentsOfDirectory(atPath: core.path)
        return names.filter { $0.hasPrefix("Tag") && $0.hasSuffix(".swift") }
            .sorted().map { core.appendingPathComponent($0) }
    }

    static func constants() throws -> [Constant] {
        let pattern = try NSRegularExpression(
            pattern: #"static\s+let\s+([A-Za-z0-9_]+)\s*=\s*Tag\(group:\s*0x([0-9A-Fa-f]{4}),\s*element:\s*0x([0-9A-Fa-f]{4})\)"#)
        var out: [Constant] = []
        for url in try tagSourceFiles() {
            let text = try String(contentsOf: url, encoding: .utf8)
            for (index, rawLine) in text.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
                let line = String(rawLine)
                let range = NSRange(line.startIndex..., in: line)
                guard let m = pattern.firstMatch(in: line, range: range) else { continue }
                func group(_ i: Int) -> String { String(line[Range(m.range(at: i), in: line)!]) }
                out.append(Constant(
                    file: url.lastPathComponent,
                    line: index + 1,
                    identifier: group(1),
                    tag: DICOMCore.Tag(group: UInt16(group(2), radix: 16)!, element: UInt16(group(3), radix: 16)!)))
            }
        }
        return out
    }

    @Test("Named Tag constants exist and are numerous")
    func constantsAreDiscovered() throws {
        let all = try Self.constants()
        #expect(all.count > 900, Comment(rawValue: "expected the DICOMCore Tag*.swift constants to be found; got \(all.count)"))
    }

    @Test("Every named Tag constant matches its PS3.6 keyword")
    func constantNamesMatchDictionaryKeyword() throws {
        var mismatches: [String] = []
        var unknown: [String] = []
        for c in try Self.constants() {
            let isPrivateOrSpecial = c.tag.group % 2 == 1 || c.tag.group == 0xFFFE
            guard let entry = DataElementDictionary.lookup(tag: c.tag) else {
                if !isPrivateOrSpecial {
                    unknown.append("\(c.file):\(c.line) \(c.identifier) \(c.tag)")
                }
                continue
            }
            let ident = Self.normalize(c.identifier)
            let ok = ident == Self.normalize(entry.keyword)
                || ident == Self.normalize(entry.name)
                || Self.allowedAliases[c.identifier] == entry.keyword
            if !ok {
                mismatches.append("\(c.file):\(c.line) '\(c.identifier)' is \(c.tag) but PS3.6 keyword is '\(entry.keyword)'")
            }
        }
        #expect(mismatches.isEmpty, Comment(rawValue: "Constant name ≠ PS3.6 keyword:\n" + mismatches.joined(separator: "\n")))
        #expect(unknown.isEmpty, Comment(rawValue: "Constant tag not in PS3.6:\n" + unknown.joined(separator: "\n")))
    }

    @Test("No tag is defined under two names in the same file")
    func noDuplicateDefinitionsPerFile() throws {
        var seen: [String: [DICOMCore.Tag: String]] = [:]
        var duplicates: [String] = []
        for c in try Self.constants() {
            if let first = seen[c.file, default: [:]][c.tag] {
                duplicates.append("\(c.file): \(c.tag) defined as '\(first)' and '\(c.identifier)'")
            } else {
                seen[c.file, default: [:]][c.tag] = c.identifier
            }
        }
        #expect(duplicates.isEmpty, Comment(rawValue: duplicates.joined(separator: "\n")))
    }

    // MARK: - Regression pins for the constants the 2026-09 audit corrected.

    @Test("Audit-corrected constants carry the PS3.6 tag")
    func auditedConstantsArePinned() {
        #expect(DICOMCore.Tag.numberOfPriorsReferenced == DICOMCore.Tag(group: 0x0072, element: 0x0014))
        #expect(DICOMCore.Tag.hangingProtocolUserIdentificationCodeSequence == DICOMCore.Tag(group: 0x0072, element: 0x000E))
        #expect(DICOMCore.Tag.hangingProtocolUserGroupName == DICOMCore.Tag(group: 0x0072, element: 0x0010))
        #expect(DICOMCore.Tag.imageSetSelectorSequence == DICOMCore.Tag(group: 0x0072, element: 0x0022))
        #expect(DICOMCore.Tag.imageSetSelectorUsageFlag == DICOMCore.Tag(group: 0x0072, element: 0x0024))
        #expect(DICOMCore.Tag.selectorAttribute == DICOMCore.Tag(group: 0x0072, element: 0x0026))
        #expect(DICOMCore.Tag.selectorValueNumber == DICOMCore.Tag(group: 0x0072, element: 0x0028))
        #expect(DICOMCore.Tag.selectorCodeSequenceValue == DICOMCore.Tag(group: 0x0072, element: 0x0080))
        #expect(DICOMCore.Tag.imageBoxSynchronizationSequence == DICOMCore.Tag(group: 0x0072, element: 0x0430))
        #expect(DICOMCore.Tag.doubleFloatRealWorldValueFirstValueMapped == DICOMCore.Tag(group: 0x0040, element: 0x9214))
        #expect(DICOMCore.Tag.doubleFloatRealWorldValueLastValueMapped == DICOMCore.Tag(group: 0x0040, element: 0x9213))
        #expect(DICOMCore.Tag.applicationSetupNumber == DICOMCore.Tag(group: 0x300A, element: 0x0234))
        #expect(DICOMCore.Tag.applicationSetupType == DICOMCore.Tag(group: 0x300A, element: 0x0232))
        #expect(DICOMCore.Tag.roiElementalCompositionSequence == DICOMCore.Tag(group: 0x3006, element: 0x00B6))
        #expect(DICOMCore.Tag.mappingResourceUID == DICOMCore.Tag(group: 0x0008, element: 0x0118))
        #expect(DICOMCore.Tag.mappingResourceName == DICOMCore.Tag(group: 0x0008, element: 0x0122))
        #expect(DICOMCore.Tag.triggerSamplePosition == DICOMCore.Tag(group: 0x0018, element: 0x106E))
        #expect(DICOMCore.Tag.waveformDataDisplayScale == DICOMCore.Tag(group: 0x003A, element: 0x0230))
        #expect(DICOMCore.Tag.unformattedTextValue == DICOMCore.Tag(group: 0x0070, element: 0x0006))
        #expect(DICOMCore.Tag.textValue == DICOMCore.Tag(group: 0x0040, element: 0xA160))
        #expect(DICOMCore.Tag.frameDimensionPointer == DICOMCore.Tag(group: 0x0028, element: 0x000A))
        #expect(DICOMCore.Tag.requestedProcedureDescription == DICOMCore.Tag(group: 0x0032, element: 0x1060))
    }

    // MARK: - Dictionary ground truth

    @Test("Repeating-group tags resolve to their base-group entry")
    func repeatingGroupsResolve() {
        #expect(DataElementDictionary.lookup(tag: DICOMCore.Tag(group: 0x6000, element: 0x0010))?.keyword == "OverlayRows")
        #expect(DataElementDictionary.lookup(tag: DICOMCore.Tag(group: 0x6002, element: 0x0010))?.keyword == "OverlayRows")
        #expect(DataElementDictionary.lookup(tag: DICOMCore.Tag(group: 0x60FE, element: 0x3000))?.keyword == "OverlayData")
        #expect(DataElementDictionary.lookup(tag: DICOMCore.Tag(group: 0x5000, element: 0x3000))?.keyword == "CurveData")
        // Odd groups in the range are private, never overlay.
        #expect(DataElementDictionary.lookup(tag: DICOMCore.Tag(group: 0x6001, element: 0x0010)) == nil)
    }

    @Test("Multi-VR attributes keep every VR, primary first")
    func multiVRPreserved() {
        #expect(DataElementDictionary.lookup(tag: .pixelData)?.vr == [.OB, .OW])
        #expect(DataElementDictionary.lookup(tag: DICOMCore.Tag(group: 0x0028, element: 0x3006))?.vr == [.US, .OW])
        #expect(DataElementDictionary.lookup(tag: DICOMCore.Tag(group: 0x7FE0, element: 0x0001))?.vr == [.OV])
    }

    @Test("Retired elements are flagged")
    func retiredFlag() {
        #expect(DataElementDictionary.lookup(tag: DICOMCore.Tag(group: 0x0020, element: 0x1020))?.retired == true)
        #expect(DataElementDictionary.lookup(tag: .patientName)?.retired == false)
    }
}
