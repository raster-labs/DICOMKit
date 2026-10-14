import Foundation
import Testing
@testable import DICOMKit
import DICOMCore

@Suite("Opt-in strict structural parsing")
struct StrictParsingTests {
    private let rows = DICOMCore.Tag(group: 0x0028, element: 0x0010)
    private let pixel = DICOMCore.Tag(group: 0x7FE0, element: 0x0010)
    private let trailer = DICOMCore.Tag(group: 0x7FE1, element: 0x0010)
    private let sequence = DICOMCore.Tag(group: 0x0008, element: 0x1115)
    private let explicitUID = "1.2.840.10008.1.2.1"
    private let implicitUID = "1.2.840.10008.1.2"

    private func u16(_ value: UInt16) -> Data {
        Data([UInt8(truncatingIfNeeded: value), UInt8(truncatingIfNeeded: value >> 8)])
    }
    private func u32(_ value: UInt32) -> Data {
        Data((0..<4).map { UInt8(truncatingIfNeeded: value >> ($0 * 8)) })
    }
    private func text(_ value: String) -> Data {
        var bytes = Data(value.utf8)
        if bytes.count % 2 != 0 { bytes.append(0) }
        return bytes
    }
    private func element(_ tag: DICOMCore.Tag, _ vr: String, _ value: Data, implicit: Bool = false,
                         length: UInt32? = nil, reserved: UInt16 = 0) -> Data {
        var bytes = u16(tag.group) + u16(tag.element)
        let count = length ?? UInt32(value.count)
        if implicit { return bytes + u32(count) + value }
        bytes += Data(vr.utf8)
        if ["OB", "OD", "OF", "OL", "OV", "OW", "SQ", "UC", "UR", "UT", "UN", "ZZ"].contains(vr) {
            bytes += u16(reserved) + u32(count)
        } else {
            bytes += u16(UInt16(count))
        }
        return bytes + value
    }
    private func marker(_ tag: DICOMCore.Tag, length: UInt32 = 0) -> Data {
        u16(tag.group) + u16(tag.element) + u32(length)
    }
    private func file(_ dataset: Data, syntax: String? = "1.2.840.10008.1.2.1",
                      extraMeta: Data = Data(), groupLengthDelta: Int = 0) -> Data {
        let transfer = syntax.map { element(.transferSyntaxUID, "UI", text($0)) } ?? Data()
        let body = transfer + extraMeta
        let length = element(DICOMCore.Tag(group: 2, element: 0), "UL", u32(UInt32(body.count + groupLengthDelta)))
        return Data(repeating: 0, count: 128) + Data("DICM".utf8) + length + body + dataset
    }
    private func image(implicit: Bool = false) -> Data {
        element(rows, "US", u16(2), implicit: implicit) + element(pixel, "OW", u16(42), implicit: implicit)
    }
    private func item(_ data: Data, undefined: Bool = false, declaredLength: UInt32? = nil) -> Data {
        marker(.item, length: declaredLength ?? (undefined ? 0xFFFFFFFF : UInt32(data.count)))
            + data + (undefined ? marker(.itemDelimitationItem) : Data())
    }
    private func sq(_ items: Data, undefined: Bool = false, declaredLength: UInt32? = nil, implicit: Bool = false) -> Data {
        element(sequence, "SQ", items, implicit: implicit, length: declaredLength ?? (undefined ? 0xFFFFFFFF : UInt32(items.count)))
            + (undefined ? marker(.sequenceDelimitationItem) : Data())
    }
    private func read(_ data: Data, options: ParsingOptions = .strict) throws -> DICOMFile {
        try DICOMFile.read(from: data, options: options)
    }

    @Test("Existing defaults stay permissive")
    func defaults() throws {
        #expect(ParsingOptions().validationPolicy == .permissive)
        #expect(ParsingOptions.default.validationPolicy == .permissive)
        #expect(ParsingOptions.metadataOnly.validationPolicy == .permissive)
        #expect(ParsingOptions.strict.validationPolicy == .strict)
        let duplicate = element(rows, "US", u16(2)) + element(rows, "US", u16(9))
        #expect(try read(file(duplicate), options: .default).dataSet.uint16(for: rows) == 9)
    }
    @Test("Full native little-endian reads retain exact pixel bytes", arguments: [false, true])
    func nativeLittleEndian(implicit: Bool) throws {
        let parsed = try read(file(image(implicit: implicit), syntax: implicit ? implicitUID : explicitUID))
        #expect(parsed.dataSet.uint16(for: rows) == 2)
        #expect(parsed.dataSet[pixel]?.valueData == u16(42))
    }
    @Test("Strict reads include valid elements after Pixel Data", arguments: [false, true])
    func validTrailer(implicit: Bool) throws {
        let bytes = file(image(implicit: implicit) + element(trailer, "LO", text("TRAILER"), implicit: implicit),
                         syntax: implicit ? implicitUID : explicitUID)
        #expect(try read(bytes).dataSet[trailer]?.valueData == text("TRAILER"))
        #expect(try read(bytes, options: .default).dataSet[trailer] == nil)
    }
    @Test("Truncated trailing headers fail instead of disappearing", arguments: [1, 2, 3, 5, 7])
    func malformedTrailer(count: Int) throws {
        let suffix = element(trailer, "LO", text("TRAILER")).prefix(count)
        let bytes = file(image() + suffix)
        #expect(throws: (any Error).self) { try read(bytes) }
        #expect(try read(bytes, options: .default).dataSet[pixel] != nil)
    }
    @Test("Truncated native pixels propagate parse failure", arguments: [false, true])
    func truncatedPixels(implicit: Bool) throws {
        let bytes = file(element(rows, "US", u16(2), implicit: implicit)
                         + element(pixel, "OW", u16(42), implicit: implicit, length: 4),
                         syntax: implicit ? implicitUID : explicitUID)
        #expect(throws: DICOMError.self) { try read(bytes) }
        #expect(try read(bytes, options: .default).dataSet[pixel] == nil)
    }
    @Test("Root duplicates are typed errors, including after Pixel Data", arguments: [false, true])
    func rootDuplicates(afterPixel: Bool) throws {
        let prefix = afterPixel ? image() : element(rows, "US", u16(2))
        do {
            _ = try read(file(prefix + element(rows, "US", u16(9))))
            Issue.record("Expected duplicate-tag failure")
        } catch StrictParsingError.duplicateTag(let tag, let offset) {
            #expect(tag == rows)
            #expect(offset >= 132)
        }
    }
    @Test("File meta duplicates fail before dictionary last-wins reduction")
    func metaDuplicate() {
        let bytes = file(image(), extraMeta: element(.transferSyntaxUID, "UI", text(explicitUID)))
        #expect(throws: StrictParsingError.self) { try read(bytes) }
    }
    @Test("Missing transfer syntax has an explicit error, preserving permissive fallback")
    func missingSyntax() throws {
        let bytes = file(image(), syntax: nil)
        #expect(throws: StrictParsingError.missingTransferSyntax) { try read(bytes) }
        #expect(try read(bytes, options: .default).dataSet[pixel] != nil)
    }
    @Test("Invalid VR is not silently recovered in dataset or meta", arguments: [false, true])
    func invalidVR(inMeta: Bool) throws {
        let bad = element(DICOMCore.Tag(group: inMeta ? 2 : 0x0009, element: 0x0010), "ZZ", Data([0, 0]))
        let bytes = inMeta ? file(image(), extraMeta: bad) : file(bad + image())
        #expect(throws: DICOMError.self) { try read(bytes) }
        #expect(try read(bytes, options: .default).dataSet[pixel] != nil)
    }
    @Test("File meta truncation and declared group-length mismatch fail")
    func malformedMeta() {
        let prefix = Data(repeating: 0, count: 128) + Data("DICM".utf8)
        #expect(throws: (any Error).self) { try read(prefix + Data([2])) }
        #expect(throws: (any Error).self) { try read(prefix + element(.transferSyntaxUID, "UI", Data([0, 0]), length: 20)) }
        #expect(throws: StrictParsingError.self) { try read(file(image(), groupLengthDelta: 2)) }
    }
    @Test("Nested duplicate scope includes defined and undefined items", arguments: [false, true])
    func nestedDuplicates(undefined: Bool) {
        let duplicate = element(rows, "US", u16(2)) + element(rows, "US", u16(9))
        #expect(throws: StrictParsingError.self) { try read(file(sq(item(duplicate, undefined: undefined), undefined: undefined))) }
    }
    @Test("Sibling item scopes allow the same tag", arguments: [false, true])
    func siblings(undefined: Bool) throws {
        let entries = item(element(rows, "US", u16(2)), undefined: undefined)
            + item(element(rows, "US", u16(9)), undefined: undefined)
        let parsed = try read(file(sq(entries, undefined: undefined)))
        #expect(parsed.dataSet[sequence]?.sequenceItems?.count == 2)
        #expect(parsed.dataSet[sequence]?.sequenceItems?[0][rows]?.uint16Value == 2)
        #expect(parsed.dataSet[sequence]?.sequenceItems?[1][rows]?.uint16Value == 9)
    }
    @Test("File-meta elements are forbidden in every dataset scope", arguments: [false, true], [false, true])
    func nestedFileMeta(implicit: Bool, undefined: Bool) {
        let meta = element(.transferSyntaxUID, "UI", text(explicitUID), implicit: implicit)
        let bytes = file(sq(item(meta, undefined: undefined), undefined: undefined, implicit: implicit),
                         syntax: implicit ? implicitUID : explicitUID)
        #expect(throws: StrictParsingError.self) { try read(bytes) }
    }
    @Test("Declared sequence and item boundaries cannot skip or overrun data")
    func explicitBoundaries() {
        let field = element(rows, "US", u16(2))
        let entries = item(field)
        let badCases = [sq(entries, declaredLength: UInt32(entries.count + 2)),
                        sq(entries, declaredLength: UInt32(entries.count - 2)),
                        sq(item(field, declaredLength: 2)),
                        sq(Data([0, 0])),
                        sq(element(rows, "US", u16(2)))]
        for bytes in badCases { #expect(throws: (any Error).self) { try read(file(bytes)) } }
    }
    @Test("Undefined scopes require complete zero-length terminators")
    func delimiters() {
        let field = element(rows, "US", u16(2))
        let valid = sq(item(field, undefined: true), undefined: true)
        let badCases = [Data(valid.dropLast(8)), Data(valid.dropLast(4)),
                        Data(valid.dropLast(4)) + u32(2),
                        sq(marker(.item, length: 0xFFFFFFFF) + field, undefined: true),
                        sq(marker(.item, length: 0xFFFFFFFF) + field + marker(.itemDelimitationItem, length: 2), undefined: true)]
        for bytes in badCases { #expect(throws: (any Error).self) { try read(file(bytes)) } }
    }
    @Test("Strict structural headers reject odd lengths, reserved bytes, and misplaced delimiters")
    func headers() {
        let badCases = [element(rows, "US", Data([1])),
                        element(pixel, "OW", u16(42), reserved: 1),
                        marker(.itemDelimitationItem),
                        element(trailer, "UN", Data(), length: 0xFFFFFFFF)]
        for bytes in badCases { #expect(throws: (any Error).self) { try read(file(bytes)) } }
    }
    @Test("Strict policy rejects partial or heuristic configurations")
    func options() {
        let bytes = file(image())
        let bad = [ParsingOptions(mode: .metadataOnly, validationPolicy: .strict),
                   ParsingOptions(mode: .lazyPixelData, validationPolicy: .strict),
                   ParsingOptions(stopAfterTag: rows, validationPolicy: .strict),
                   ParsingOptions(maxElements: 0, validationPolicy: .strict)]
        for options in bad { #expect(throws: StrictParsingError.invalidOptions) { try read(bytes, options: options) } }
        #expect(throws: StrictParsingError.invalidOptions) { try DICOMFile.read(from: bytes, force: true, options: .strict) }
    }
    @Test("Element cap fails rather than returning partial success")
    func limits() throws {
        #expect(throws: StrictParsingError.elementLimitExceeded(1)) { try read(file(image()), options: ParsingOptions(maxElements: 1, validationPolicy: .strict)) }
        #expect(try read(file(image()), options: ParsingOptions(maxElements: 2, validationPolicy: .strict)).dataSet[pixel] != nil)
    }
    @Test("Unsupported strict transfer syntaxes fail explicitly", arguments: ["1.2.840.10008.1.2.2", "1.2.840.10008.1.2.1.99", "1.2.840.10008.1.2.4.50"])
    func unsupportedSyntax(uid: String) {
        #expect(throws: StrictParsingError.unsupportedTransferSyntax(uid)) { try read(file(image(), syntax: uid)) }
    }

    private func compressedOptions(_ uid: String, bytes: Int = 12, fragments: Int = 2,
                                   generalElements: Int? = nil, rootElements: Int? = nil,
                                   strictElements: Int = 100_000, materializedBytes: Int = 512 * 1024 * 1024) -> ParsingOptions {
        ParsingOptions(maxElements: rootElements, maxTotalElements: generalElements, maxFragmentCount: fragments,
            strictEncapsulation: true, maximumEncapsulatedBytes: bytes, allowedTransferSyntaxUIDs: [uid],
            validationPolicy: .strict, strictResourceLimits: .init(maximumTotalElements: strictElements,
                maximumMaterializedValueBytes: materializedBytes))
    }

    // Synthetic envelope bytes exercise structural admission, not codec/sample correctness.
    private func encapsulated(bot: Data? = nil, fragments: [Data] = [Data([1, 2]), Data([3, 4])],
                              vr: String = "OB", reserved: UInt16 = 0, length: UInt32 = 0xFFFFFFFF,
                              delimiterLength: UInt32 = 0) -> Data {
        let table = bot ?? (u32(0) + u32(10))
        var value = marker(.item, length: UInt32(table.count)) + table
        for fragment in fragments { value += marker(.item, length: UInt32(fragment.count)) + fragment }
        value += marker(.sequenceDelimitationItem, length: delimiterLength)
        return element(pixel, vr, value, length: length, reserved: reserved)
    }

    @Test("Finite strict compression is explicit and retains complete trailing metadata",
          arguments: ["1.2.840.10008.1.2.4.50", "1.2.840.10008.1.2.4.70", "1.2.840.10008.1.2.4.80"])
    func finiteCompressedAdmission(uid: String) throws {
        let bytes = file(element(rows, "US", u16(2)) + encapsulated() + element(trailer, "LO", text("TRAILER")), syntax: uid)
        #expect(throws: StrictParsingError.unsupportedTransferSyntax(uid)) { try read(bytes) }
        let parsed = try read(bytes, options: compressedOptions(uid))
        #expect(parsed.dataSet[pixel]?.encapsulatedFragments == [Data([1, 2]), Data([3, 4])])
        #expect(parsed.dataSet[pixel]?.encapsulatedOffsetTable == [0, 10])
        #expect(parsed.dataSet[trailer]?.valueData == text("TRAILER"))
        #expect(try read(bytes, options: .default).dataSet[trailer] == nil)
    }

    @Test("Explicit finite policy preserves both native encodings", arguments: [false, true])
    func finiteNativeAdmission(implicit: Bool) throws {
        let uid = implicit ? implicitUID : explicitUID
        #expect(try read(file(image(implicit: implicit), syntax: uid), options: compressedOptions(uid))
            .dataSet[pixel]?.valueData == u16(42))
    }

    @Test("Strict compressed policy cannot omit encapsulation or enable an unqualified syntax")
    func finitePolicyOptions() {
        let uid = "1.2.840.10008.1.2.4.50"
        let bytes = file(encapsulated(), syntax: uid)
        let invalid = [ParsingOptions(allowedTransferSyntaxUIDs: [uid], validationPolicy: .strict),
                       compressedOptions(uid, bytes: 0), compressedOptions(uid, fragments: 0)]
        for options in invalid {
            #expect(throws: StrictParsingError.invalidOptions) { try read(bytes, options: options) }
        }
        for other in ["1.2.840.10008.1.2.2", "1.2.840.10008.1.2.1.99", "1.2.840.10008.1.2.4.51",
                      "1.2.840.10008.1.2.4.57", "1.2.840.10008.1.2.4.81", "1.2.840.10008.1.2.4.90", "1.2.840.10008.1.2.5"] {
            #expect(throws: StrictParsingError.invalidOptions) { try read(bytes, options: compressedOptions(other)) }
        }
        #expect(throws: StrictParsingError.unsupportedTransferSyntax(uid)) {
            try read(bytes, options: compressedOptions("1.2.840.10008.1.2.4.70"))
        }
    }

    @Test("Compressed strict reads reject malformed or duplicate elements after pixels")
    func compressedFullTail() {
        let uid = "1.2.840.10008.1.2.4.50"
        let options = compressedOptions(uid)
        let suffixes = [Data([0x28]), Data([0x28, 0]), encapsulated(),
                        element(.transferSyntaxUID, "UI", text(uid)),
                        element(trailer, "LO", text("A")) + element(trailer, "LO", text("B"))]
        for suffix in suffixes {
            #expect(throws: (any Error).self) { try read(file(encapsulated() + suffix, syntax: uid), options: options) }
        }
        #expect(throws: StrictParsingError.self) {
            try read(file(encapsulated(), syntax: uid, groupLengthDelta: 2), options: options)
        }
        let duplicate = element(rows, "US", u16(2)) + element(rows, "US", u16(9))
        #expect(throws: StrictParsingError.self) {
            try read(file(sq(item(duplicate)) + encapsulated(), syntax: uid), options: options)
        }
    }

    @Test("Compressed Pixel Data counts once against root and both aggregate element limits")
    func compressedElementBudgets() throws {
        let uid = "1.2.840.10008.1.2.4.50"
        let bytes = file(encapsulated(), syntax: uid) // Two FMI elements and one Pixel Data element.
        #expect(try read(bytes, options: compressedOptions(uid, generalElements: 3, rootElements: 1, strictElements: 3))
            .dataSet[pixel] != nil)
        #expect(throws: StrictParsingError.resourceLimitExceeded(resource: .totalElements, limit: 2)) {
            try read(bytes, options: compressedOptions(uid, strictElements: 2))
        }
        #expect(throws: DICOMError.self) { try read(bytes, options: compressedOptions(uid, generalElements: 2)) }
        #expect(throws: StrictParsingError.elementLimitExceeded(1)) {
            try read(file(encapsulated() + element(trailer, "LO", text("A")), syntax: uid),
                     options: compressedOptions(uid, rootElements: 1))
        }
    }

    @Test("Maintained envelope and separate materialized budgets enforce exact boundaries")
    func compressedByteBudgets() throws {
        let uid = "1.2.840.10008.1.2.4.50"
        let bytes = file(encapsulated(), syntax: uid)
        let metaBytes = 4 + text(uid).count
        #expect(try read(bytes, options: compressedOptions(uid, materializedBytes: metaBytes)).dataSet[pixel] != nil)
        #expect(throws: StrictParsingError.resourceLimitExceeded(resource: .materializedValueBytes, limit: metaBytes - 1)) {
            try read(bytes, options: compressedOptions(uid, materializedBytes: metaBytes - 1))
        }
        #expect(throws: DICOMError.self) { try read(bytes, options: compressedOptions(uid, bytes: 11)) }
        #expect(throws: DICOMError.self) { try read(bytes, options: compressedOptions(uid, fragments: 1)) }
        // Empty BOT still charges/counts every fragment through the maintained envelope.
        let emptyBOT = file(encapsulated(bot: Data()), syntax: uid)
        #expect(try read(emptyBOT, options: compressedOptions(uid, bytes: 4)).dataSet[pixel] != nil)
        #expect(throws: DICOMError.self) { try read(emptyBOT, options: compressedOptions(uid, bytes: 3)) }
        #expect(throws: DICOMError.self) { try read(emptyBOT, options: compressedOptions(uid, fragments: 1)) }
    }

    @Test("Combined strict policy retains maintained malformed-envelope rejection")
    func compressedMalformedEnvelope() {
        let uid = "1.2.840.10008.1.2.4.50"
        let bad = [encapsulated(vr: "OW"), encapsulated(reserved: 1), encapsulated(length: 4),
                   encapsulated(delimiterLength: 2), Data(encapsulated().dropLast(8)), Data(encapsulated().dropLast(4)),
                   encapsulated(bot: Data([0, 0])), encapsulated(bot: u32(2) + u32(10)),
                   encapsulated(bot: u32(0) + u32(9)), encapsulated(bot: u32(0) + u32(0)),
                   encapsulated(bot: Data(), fragments: []), encapsulated(bot: Data(), fragments: [Data()]),
                   encapsulated(bot: Data(), fragments: [Data([1])])]
        for value in bad {
            #expect(throws: (any Error).self) { try read(file(value, syntax: uid), options: compressedOptions(uid)) }
        }
    }

    private func bounded(_ limits: ParsingOptions.StrictResourceLimits, maxElements: Int? = nil) -> ParsingOptions {
        ParsingOptions(maxElements: maxElements, validationPolicy: .strict, strictResourceLimits: limits)
    }

    @Test("Strict input cap includes all Part 10 bytes and accepts the exact boundary")
    func inputResourceLimit() throws {
        let bytes = file(image())
        #expect(try read(bytes, options: bounded(.init(maximumInputBytes: bytes.count))).dataSet[pixel] != nil)
        #expect(throws: StrictParsingError.resourceLimitExceeded(resource: .inputBytes, limit: bytes.count - 1)) {
            try read(bytes, options: bounded(.init(maximumInputBytes: bytes.count - 1)))
        }
        // Resource failure precedes even prefix parsing on over-budget input.
        #expect(throws: StrictParsingError.resourceLimitExceeded(resource: .inputBytes, limit: 1)) {
            try read(Data([0, 0]), options: bounded(.init(maximumInputBytes: 1)))
        }
    }

    @Test("Strict URL ingestion checks exact EOF and refuses oversized files")
    func urlInputResourceLimit() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("dicom-strict-\(UUID().uuidString).dcm")
        defer { try? FileManager.default.removeItem(at: url) }
        // Cross a read-chunk boundary and use native Pixel Data, not a test-only reader.
        let bytes = file(element(pixel, "OW", Data(repeating: 0, count: 70_000)))
        try bytes.write(to: url)
        let exact = bounded(.init(maximumInputBytes: bytes.count))
        #expect(try DICOMFile.read(from: url, options: exact).dataSet[pixel]?.valueData.count == 70_000)
        #expect(throws: StrictParsingError.resourceLimitExceeded(resource: .inputBytes, limit: bytes.count - 1)) {
            try DICOMFile.read(from: url, options: bounded(.init(maximumInputBytes: bytes.count - 1)))
        }
        #expect(throws: StrictParsingError.invalidOptions) {
            try DICOMFile.read(from: url, options: bounded(.init(maximumInputBytes: 0)))
        }
        #expect(throws: StrictParsingError.invalidOptions) {
            try DICOMFile.read(from: URL(string: "https://example.invalid/image.dcm")!, options: .strict)
        }
    }

    @Test("Aggregate element cap covers file meta, nested siblings, SQ and native pixels", arguments: [false, true], [false, true])
    func aggregateElementResourceLimit(implicit: Bool, undefined: Bool) throws {
        let leaf = element(rows, "US", u16(2), implicit: implicit)
        let inner = sq(item(leaf, undefined: undefined), undefined: undefined, implicit: implicit)
        let outer = sq(item(inner, undefined: undefined) + item(leaf, undefined: undefined), undefined: undefined, implicit: implicit)
        // 2 file-meta elements + outer SQ + inner SQ + 2 leaves + root pixel.
        let bytes = file(outer + element(pixel, "OW", u16(1), implicit: implicit), syntax: implicit ? implicitUID : explicitUID)
        #expect(try read(bytes, options: bounded(.init(maximumTotalElements: 7))).dataSet[pixel] != nil)
        #expect(throws: StrictParsingError.resourceLimitExceeded(resource: .totalElements, limit: 6)) {
            try read(bytes, options: bounded(.init(maximumTotalElements: 6)))
        }
        #expect(throws: StrictParsingError.resourceLimitExceeded(resource: .totalElements, limit: 1)) {
            try read(bytes, options: bounded(.init(maximumTotalElements: 1)))
        }
        // maxElements retains its root-only meaning; nested elements and meta do not consume it.
        #expect(try read(file(outer, syntax: implicit ? implicitUID : explicitUID),
                         options: bounded(.init(maximumTotalElements: 6), maxElements: 1)).dataSet[sequence] != nil)
    }

    @Test("Sequence depth is checked before descent and unwinds across sibling items", arguments: [false, true], [false, true])
    func depthResourceLimit(implicit: Bool, undefined: Bool) throws {
        let leaf = element(rows, "US", u16(2), implicit: implicit)
        let inner = sq(item(leaf, undefined: undefined), undefined: undefined, implicit: implicit)
        let outer = sq(item(inner, undefined: undefined) + item(inner, undefined: undefined), undefined: undefined, implicit: implicit)
        let bytes = file(outer, syntax: implicit ? implicitUID : explicitUID)
        #expect(try read(bytes, options: bounded(.init(maximumSequenceDepth: 2))).dataSet[sequence]?.sequenceItems?.count == 2)
        #expect(throws: StrictParsingError.resourceLimitExceeded(resource: .sequenceDepth, limit: 1)) {
            try read(bytes, options: bounded(.init(maximumSequenceDepth: 1)))
        }
        // Exercise the complete accepted depth on the test worker's real stack.
        var accepted = leaf
        for _ in 0..<32 { accepted = sq(item(accepted, undefined: undefined), undefined: undefined, implicit: implicit) }
        #expect(try read(file(accepted, syntax: implicit ? implicitUID : explicitUID)).dataSet[sequence] != nil)
        var adversarial = leaf
        for _ in 0..<1_000 { adversarial = sq(item(adversarial, undefined: undefined), undefined: undefined, implicit: implicit) }
        #expect(throws: StrictParsingError.resourceLimitExceeded(resource: .sequenceDepth, limit: 32)) {
            try read(file(adversarial, syntax: implicit ? implicitUID : explicitUID))
        }
    }

    @Test("Sequence item cap is aggregate and includes empty items", arguments: [false, true], [false, true])
    func itemResourceLimit(implicit: Bool, undefined: Bool) throws {
        let empty = item(Data(), undefined: undefined)
        let inner = sq(empty + empty, undefined: undefined, implicit: implicit)
        let outer = sq(item(inner, undefined: undefined) + empty, undefined: undefined, implicit: implicit)
        let bytes = file(outer, syntax: implicit ? implicitUID : explicitUID)
        // Outer nonempty item + two nested empty items + outer empty item.
        #expect(try read(bytes, options: bounded(.init(maximumSequenceItems: 4))).dataSet[sequence]?.sequenceItems?.count == 2)
        #expect(throws: StrictParsingError.resourceLimitExceeded(resource: .sequenceItems, limit: 3)) {
            try read(bytes, options: bounded(.init(maximumSequenceItems: 3)))
        }
        let emptyFlood = (0..<1_000).reduce(into: Data()) { value, _ in value += empty }
        #expect(throws: StrictParsingError.resourceLimitExceeded(resource: .sequenceItems, limit: 5)) {
            try read(file(sq(emptyFlood, undefined: undefined, implicit: implicit), syntax: implicit ? implicitUID : explicitUID),
                     options: bounded(.init(maximumSequenceItems: 5)))
        }
    }

    @Test("Materialized byte cap counts meta, leaf data and every enclosing raw SQ copy", arguments: [false, true], [false, true])
    func valueResourceLimit(implicit: Bool, undefined: Bool) throws {
        let leaf = element(rows, "US", u16(2), implicit: implicit)
        let innerItems = item(leaf, undefined: undefined)
        let inner = sq(innerItems, undefined: undefined, implicit: implicit)
        let outerItems = item(inner, undefined: undefined)
        let syntax = implicit ? implicitUID : explicitUID
        let bytes = file(sq(outerItems, undefined: undefined, implicit: implicit), syntax: syntax)
        let metaBytes = 4 + text(syntax).count
        let copiedBytes = metaBytes + 2 + innerItems.count + outerItems.count + (undefined ? 16 : 0)
        #expect(try read(bytes, options: bounded(.init(maximumMaterializedValueBytes: copiedBytes))).dataSet[sequence] != nil)
        #expect(throws: StrictParsingError.resourceLimitExceeded(resource: .materializedValueBytes, limit: copiedBytes - 1)) {
            try read(bytes, options: bounded(.init(maximumMaterializedValueBytes: copiedBytes - 1)))
        }
        #expect(throws: StrictParsingError.resourceLimitExceeded(resource: .materializedValueBytes, limit: 3)) {
            try read(bytes, options: bounded(.init(maximumMaterializedValueBytes: 3)))
        }
    }

    @Test("Native Pixel Data participates in cumulative value-byte limits", arguments: [false, true])
    func pixelValueResourceLimit(implicit: Bool) throws {
        let syntax = implicit ? implicitUID : explicitUID
        let bytes = file(image(implicit: implicit), syntax: syntax)
        let total = 4 + text(syntax).count + 2 + 2
        #expect(try read(bytes, options: bounded(.init(maximumMaterializedValueBytes: total))).dataSet[pixel] != nil)
        #expect(throws: StrictParsingError.resourceLimitExceeded(resource: .materializedValueBytes, limit: total - 1)) {
            try read(bytes, options: bounded(.init(maximumMaterializedValueBytes: total - 1)))
        }
    }

    @Test("Nonpositive strict budgets are rejected; permissive parsing ignores them", arguments: [0, -1])
    func invalidResourceLimits(value: Int) throws {
        let budgets: [ParsingOptions.StrictResourceLimits] = [
            .init(maximumInputBytes: value), .init(maximumSequenceDepth: value),
            .init(maximumTotalElements: value), .init(maximumSequenceItems: value),
            .init(maximumMaterializedValueBytes: value)
        ]
        let bytes = file(sq(item(element(rows, "US", u16(2)))) + image())
        for budget in budgets {
            #expect(throws: StrictParsingError.invalidOptions) { try read(bytes, options: bounded(budget)) }
            #expect(try read(bytes, options: ParsingOptions(strictResourceLimits: budget)).dataSet[pixel] != nil)
        }
        let tiny = ParsingOptions.StrictResourceLimits(maximumInputBytes: 1, maximumSequenceDepth: 1,
            maximumTotalElements: 1, maximumSequenceItems: 1, maximumMaterializedValueBytes: 1)
        #expect(try read(bytes, options: ParsingOptions(strictResourceLimits: tiny)).dataSet[pixel] != nil)
        #expect(try read(file(image()), options: ParsingOptions(maxElements: 1)).dataSet[pixel] == nil)
    }

    @Test("Large configured limits and adversarial declared lengths fail without arithmetic overflow")
    func resourceArithmetic() throws {
        let limits = ParsingOptions.StrictResourceLimits(maximumInputBytes: Int.max, maximumSequenceDepth: Int.max,
            maximumTotalElements: Int.max, maximumSequenceItems: Int.max, maximumMaterializedValueBytes: Int.max)
        #expect(try read(file(image()), options: bounded(limits)).dataSet[pixel] != nil)
        let huge: UInt32 = 0xFFFFFFFE
        for bytes in [element(pixel, "OW", Data(), length: huge), sq(Data(), declaredLength: huge),
                      sq(item(Data(), declaredLength: huge))] {
            do {
                _ = try read(file(bytes), options: bounded(limits))
                Issue.record("Expected a bounded truncated-value failure")
            } catch DICOMError.unexpectedEndOfData {}
        }
    }

    @Test func directoryWriterIncludesMetaLengthAndStableOffsets() throws {
        let image = DirectoryRecord.image(referencedFileID: ["DICOM", "IM000001"],
            sopClassUID: "1.2.840.10008.5.1.4.1.1.2", sopInstanceUID: "2.25.99001",
            transferSyntaxUID: explicitUID, instanceNumber: "1")
        var series = DirectoryRecord.series(seriesInstanceUID: "2.25.99002", modality: "CT", seriesNumber: "1")
        series.children = [image]
        var study = DirectoryRecord.study(studyInstanceUID: "2.25.99003", studyDate: "20260101", studyTime: "120000")
        study.children = [series]
        var patient = DirectoryRecord.patient(patientID: "TEST", patientName: "SYNTHETIC")
        patient.children = [study]
        let bytes = try DICOMDIRWriter.write(DICOMDirectory(fileSetID: "TEST", rootRecords: [patient]))
        let file = try DICOMFile.read(from: bytes, options: .init(validationPolicy: .strict))
        #expect(file.fileMetaInformation[.fileMetaInformationGroupLength] != nil)
        let fields = try DICOMMetadataDiscovery.read(byteCount: bytes.count, retaining: []) { offset, count in
            bytes.subdata(in: offset..<(offset + count))
        }
        #expect(fields.directoryRecords.count == 4)
        let directory = try DICOMDIRReader.read(from: bytes)
        #expect(directory.rootRecords.count == 1)
        #expect(directory.allRecords().last?.referencedSOPInstanceUID == "2.25.99001")
        let offset = try #require(file.dataSet[Tag(group: 0x0004, element: 0x1200)]?.uint32Value)
        #expect(bytes.subdata(in: Int(offset)..<(Int(offset) + 4)) == Data([0xFE, 0xFF, 0x00, 0xE0]))
    }

}
