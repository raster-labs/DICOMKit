// NEMA-verified: 2026a, checked 2026-10-14 — storage adapter; DICOM grammar remains in DICOMParser.
import Foundation
import DICOMCore

/// Strictly parsed structure with deferred, verified values. This deliberately is
/// not a `DICOMFile`: no empty placeholder value is exposed as materialized data.
public struct BoundedDICOMFile: Sendable {
    private let index: BoundedParseCapture
    /// Admitted Transfer Syntax UID from the verified file meta information.
    public let transferSyntaxUID: String
    /// SHA-256 identity of the complete source captured before parsing.
    public var contentIdentity: String { index.source.identity }
    /// Complete source length in bytes.
    public var sourceByteCount: Int { index.source.count }
    /// Deferred view of the file meta information scope.
    public var fileMetaInformation: BoundedDICOMDataSet { BoundedDICOMDataSet(index: index, scope: 0) }
    /// Deferred view of the root dataset scope.
    public var dataSet: BoundedDICOMDataSet { BoundedDICOMDataSet(index: index, scope: 1) }
    /// Current shared-ledger snapshot, including other owners using the same budget.
    public var allocationReceipt: DICOMAllocationReceipt { index.budget.receipt }
    init(index: BoundedParseCapture, transferSyntaxUID: String) {
        self.index = index; self.transferSyntaxUID = transferSyntaxUID
    }
    /// Recheck the anchored source before handing a result to a consumer.
    public func validateSource() throws { try index.source.validate() }
}

/// A scope view shares the source and all index backing. Creating another view
/// neither duplicates its payload nor releases the original allocation charge.
public struct BoundedDICOMDataSet: Sendable {
    fileprivate let index: BoundedParseCapture
    fileprivate let scope: Int
    /// Number of immediate elements in this scope, excluding nested items.
    public var count: Int { index.scopes[scope].elementCount }
    /// Find an immediate element without constructing a metadata dictionary.
    public subscript(tag: Tag) -> BoundedDICOMElement? {
        var node = index.scopes[scope].firstElement
        while node >= 0 {
            let record = index.elements[node]
            if record.tag == tag { return BoundedDICOMElement(index: index, identifier: node) }
            node = record.nextSibling
        }
        return nil
    }
    /// Enumerate without constructing another array/dictionary of metadata.
    public func forEach(_ body: (BoundedDICOMElement) throws -> Void) rethrows {
        var node = index.scopes[scope].firstElement
        while node >= 0 {
            try body(BoundedDICOMElement(index: index, identifier: node))
            node = index.elements[node].nextSibling
        }
    }
}

/// A deferred value/sequence view. Every acquisition can fail if the source
/// changes, a budget rejects the allocation, or the worker is cancelled.
public struct BoundedDICOMElement: Sendable {
    fileprivate let index: BoundedParseCapture
    fileprivate let identifier: Int
    private var record: BoundedParseCapture.Element { index.elements[identifier] }
    /// Element tag from the canonical parser.
    public var tag: Tag { record.tag }
    /// Explicit or dictionary-resolved value representation.
    public var vr: VR { record.vr }
    /// Declared value length, including the undefined-length sentinel where applicable.
    public var length: UInt32 { record.length }
    /// Byte order used to interpret this element's value.
    public var byteOrder: ByteOrder { record.byteOrder }
    /// Verified raw value span length, including sequence encoding where applicable.
    public var valueByteCount: Int { record.range.count }
    /// Number of encapsulated payload fragments, excluding the Basic Offset Table.
    public var fragmentCount: Int { record.fragmentCount }
    /// Whether the parser captured an encapsulated Pixel Data envelope.
    public var isEncapsulated: Bool { record.botRange != nil }
    /// Number of immediate sequence items.
    public var itemCount: Int { record.itemCount }

    /// Acquire the complete raw value span with an independent controlled backing.
    /// - Parameter resource: Allocation class charged until the returned storage is destroyed.
    /// - Returns: Immutable bytes verified against the captured source identity.
    public func readValue(resource: DICOMAllocationClass = .metadata) throws -> DICOMByteBuffer {
        try index.source.read(record.range, resource: resource)
    }
    /// Visit immediate sequence items without materializing their deferred values.
    /// - Parameter body: Receives a view retaining the same source and index backing.
    public func forEachItem(_ body: (BoundedDICOMDataSet) throws -> Void) rethrows {
        var item = record.firstItem
        while item >= 0 {
            try body(BoundedDICOMDataSet(index: index, scope: item))
            item = index.scopes[item].nextItem
        }
    }
    /// Read a selected native frame range without materializing the other frames.
    /// Descriptor and frame-size qualification remain the caller's existing owner.
    public func readValueRange(_ relativeRange: Range<Int>, resource: DICOMAllocationClass = .encoded) throws -> DICOMByteBuffer {
        guard relativeRange.lowerBound >= 0, relativeRange.upperBound <= record.range.count else {
            throw DICOMError.parsingFailed("Value range outside element")
        }
        let start = record.range.lowerBound + relativeRange.lowerBound
        let end = record.range.lowerBound + relativeRange.upperBound
        return try index.source.read(start..<end, resource: resource)
    }
    /// Only the finite UID token is retained, while arbitrary legacy padding is
    /// validated incrementally. Existing strict admission must not be tightened
    /// merely because deferred storage no longer materializes a large UI value.
    func transferSyntaxToken() throws -> String {
        let cursor = DICOMParserInput(source: index.source)
        let range = record.range
        var position = range.lowerBound, used = 0
        var trailingPadding = false, invalidToken = false
        let token = try DICOMByteBuffer(count: 64, budget: index.budget, resource: .metadata) { output in
            while position < range.upperBound {
                try Task.checkCancellation()
                let scalarStart = position
                guard let scalar = try cursor.scalar(at: &position, end: range.upperBound) else {
                    throw StrictParsingError.missingTransferSyntax
                }
                if scalarStart == range.lowerBound && scalar.value == 0xFEFF { continue }
                let padded = scalar.value == 0 || CharacterSet.whitespacesAndNewlines.contains(scalar)
                if padded { if used > 0 { trailingPadding = true }; continue }
                if trailingPadding || scalar.value > 127 || used >= output.count { invalidToken = true }
                else { output[used] = UInt8(scalar.value); used += 1 }
            }
        }
        guard used > 0 || invalidToken else { throw StrictParsingError.missingTransferSyntax }
        guard !invalidToken else { throw StrictParsingError.unsupportedTransferSyntax("unrecognized Transfer Syntax UID") }
        return token.withUnsafeBytes { String(decoding: $0.prefix(used), as: UTF8.self) }
    }

    /// Acquire one complete compressed frame using the maintained frame mapper.
    /// The complete map is validated before allocating the selected codestream.
    /// Extended offsets are an explicit separate profile and not inferred here.
    public func readFrame(at frame: Int, numberOfFrames: Int,
                          maximumBytes: Int = 64 * 1024 * 1024) throws -> DICOMByteBuffer {
        let record = self.record
        guard let bot = record.botRange, frame >= 0, frame < numberOfFrames,
              maximumBytes >= 0 else { throw DICOMError.parsingFailed("Invalid encapsulated frame selection") }
        let cursor = DICOMParserInput(source: index.source)
        var selected: Range<Int>?
        let valid = try EncapsulatedPixelData.visitFrameGroups(numberOfFrames: numberOfFrames,
            fragmentCount: record.fragmentCount,
            fragmentLength: { index.fragments[record.firstFragment + $0].range.count },
            offsetCount: bot.count / 4,
            offsetAt: { position in
                guard let value = try cursor.readUInt32LE(at: bot.lowerBound + position * 4) else {
                    throw DICOMError.unexpectedEndOfData
                }
                return UInt64(value)
            }, extended: false) { position, range, _ in
                if position == frame { selected = range }
            }
        guard valid, let selected else { throw DICOMError.parsingFailed("Invalid encapsulated frame mapping") }
        var total = 0
        for fragment in selected {
            let length = index.fragments[record.firstFragment + fragment].range.count
            guard total <= maximumBytes, length <= maximumBytes - total else {
                throw DICOMError.limitExceeded("Selected encoded frame exceeds byte budget")
            }
            total += length
        }
        try index.source.validate()
        let output = try DICOMByteBuffer(count: total, budget: index.budget, resource: .encoded) { bytes in
            var offset = 0
            for fragment in selected {
                let range = index.fragments[record.firstFragment + fragment].range
                try index.source.copy(range, to: UnsafeMutableRawBufferPointer(rebasing: bytes[offset..<offset + range.count]))
                offset += range.count
            }
        }
        try index.source.validate()
        return output
    }

}

/// Mutable only during the synchronous parse; no builder escapes before seal.
/// Fixed-layout records have no owned variable-size payloads.
final class BoundedParseCapture: @unchecked Sendable {
    struct Scope {
        var firstElement = -1, lastElement = -1, elementCount = 0, nextItem = -1
    }
    struct Element {
        let tag: Tag, vr: VR, length: UInt32, byteOrder: ByteOrder
        var range: Range<Int>
        var nextSibling = -1, firstItem = -1, lastItem = -1, itemCount = 0
        var firstFragment = -1, fragmentCount = 0
        var botRange: Range<Int>?
    }
    struct Fragment { let range: Range<Int>; let streamOffset: Int }
    private struct Membership { var scope = -1; var tag: UInt32 = 0 }
    let source: any DICOMVerifiedByteSource
    let budget: DICOMAllocationBudget
    let scopes: DICOMStorageVector<Scope>
    let elements: DICOMStorageVector<Element>
    let fragments: DICOMStorageVector<Fragment>
    private var membership: DICOMStorageVector<Membership>
    private var membershipCount = 0
    private var sealed = false
    var currentScope = 0
    var currentSequence = -1

    init(source: any DICOMVerifiedByteSource) throws {
        self.source = source; budget = source.allocationBudget
        scopes = try DICOMStorageVector(budget: budget)
        elements = try DICOMStorageVector(budget: budget)
        fragments = try DICOMStorageVector(budget: budget)
        membership = try DICOMStorageVector(budget: budget)
        try scopes.append(Scope()); try scopes.append(Scope())
    }
    func seal() throws { try source.validate(); membership.releaseStorage(); sealed = true }
    func append(tag: Tag, vr: VR, length: UInt32, byteOrder: ByteOrder, range: Range<Int>) throws -> Int {
        precondition(!sealed)
        let identifier = elements.count
        try elements.append(Element(tag: tag, vr: vr, length: length, byteOrder: byteOrder, range: range))
        var scope = scopes[currentScope]
        if scope.lastElement >= 0 { elements[scope.lastElement].nextSibling = identifier }
        else { scope.firstElement = identifier }
        scope.lastElement = identifier; scope.elementCount += 1
        scopes[currentScope] = scope
        return identifier
    }
    func beginItem() throws -> Int {
        precondition(!sealed && currentSequence >= 0)
        let previous = currentScope
        let identifier = scopes.count
        try scopes.append(Scope())
        var sequence = elements[currentSequence]
        if sequence.lastItem >= 0 { scopes[sequence.lastItem].nextItem = identifier }
        else { sequence.firstItem = identifier }
        sequence.lastItem = identifier; sequence.itemCount += 1
        elements[currentSequence] = sequence; currentScope = identifier
        return previous
    }
    func setRange(_ range: Range<Int>, for identifier: Int) { elements[identifier].range = range }
    func setBOT(_ range: Range<Int>, for identifier: Int) { elements[identifier].botRange = range }
    func appendFragment(_ range: Range<Int>, streamOffset: Int, to identifier: Int) throws {
        if elements[identifier].firstFragment < 0 { elements[identifier].firstFragment = fragments.count }
        try fragments.append(Fragment(range: range, streamOffset: streamOffset))
        elements[identifier].fragmentCount += 1
    }
    func record(_ tag: Tag, at offset: Int) throws {
        let key = UInt32(tag.group) << 16 | UInt32(tag.element)
        if membership.count == 0 || membershipCount >= membership.count / 2 { try growMembership() }
        let slot = find(scope: currentScope, tag: key, in: membership)
        guard membership[slot].scope < 0 else { throw StrictParsingError.duplicateTag(tag: tag, offset: offset) }
        membership[slot] = Membership(scope: currentScope, tag: key)
        membershipCount += 1
    }
    private func find(scope: Int, tag: UInt32, in table: DICOMStorageVector<Membership>) -> Int {
        var bits = (UInt64(scope) << 32 | UInt64(tag)) &* 0x9e3779b97f4a7c15
        bits ^= bits >> 32
        var slot = Int(bits & UInt64(table.count - 1))
        while table[slot].scope >= 0 && (table[slot].scope != scope || table[slot].tag != tag) {
            slot = (slot + 1) & (table.count - 1)
        }
        return slot
    }
    private func growMembership() throws {
        let (capacity, overflow) = max(512, membership.count).multipliedReportingOverflow(by: membership.count == 0 ? 1 : 2)
        guard !overflow else { throw DICOMAllocationError.invalidSize }
        let next = try DICOMStorageVector<Membership>(budget: budget)
        for _ in 0..<capacity { try next.append(Membership()) }
        for index in 0..<membership.count {
            let entry = membership[index]
            if entry.scope >= 0 { next[find(scope: entry.scope, tag: entry.tag, in: next)] = entry }
        }
        membership = next
    }
}
