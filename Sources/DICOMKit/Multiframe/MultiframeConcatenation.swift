// NEMA-verified: 2026a, checked 2026-09-29 — Concatenation attributes per PS3.3 2026a C.7.6.16.2.2
import Foundation
import DICOMCore
#if canImport(CryptoKit)
import CryptoKit
#endif

// MARK: - Deterministic per-frame UIDs

/// Instance UIDs derived from the source instance so a split is reproducible and
/// references between multi-frame objects can be rewritten to the frames they
/// name (dcm4che `emf2sf` derives `<mapped>.N` the same way).
public enum MultiframeInstanceUIDs {

    /// A `2.25.<128-bit decimal>` UID (PS3.5 B.2) derived from the source SOP
    /// Instance UID and the 0-based frame index. Same inputs → same UID.
    public static func derived(from sourceSOPInstanceUID: String, frame: Int, salt: String = "") -> String {
        let key = "\(MultiframeSOPClassMap.normalize(sourceSOPInstanceUID))#\(frame)\(salt)"
        return "2.25." + decimal128(of: key)
    }

    /// A derived Series Instance UID for a stack / temporal group of a split.
    public static func derivedSeries(from seriesInstanceUID: String, group: String) -> String {
        "2.25." + decimal128(of: "series:\(MultiframeSOPClassMap.normalize(seriesInstanceUID))#\(group)")
    }

    /// Decimal rendering of the first 128 bits of SHA-256(key) (never zero-prefixed).
    static func decimal128(of key: String) -> String {
        let bytes: [UInt8]
        #if canImport(CryptoKit)
        bytes = Array(SHA256.hash(data: Data(key.utf8))).prefix(16).map { $0 }
        #else
        // FNV-1a folded twice: not cryptographic, but stable across runs.
        var h1: UInt64 = 0xcbf29ce484222325, h2: UInt64 = 0x84222325cbf29ce4
        for b in key.utf8 {
            h1 = (h1 ^ UInt64(b)) &* 0x100000001b3
            h2 = (h2 ^ UInt64(b)) &* 0x100000001b3 &+ 0x9e3779b97f4a7c15
        }
        bytes = withUnsafeBytes(of: h1.bigEndian) { Array($0) } + withUnsafeBytes(of: h2.bigEndian) { Array($0) }
        #endif
        // Base-256 → base-10 by repeated division on 32-bit limbs.
        var limbs = bytes.map { UInt32($0) }
        var digits: [Character] = []
        while limbs.contains(where: { $0 != 0 }) {
            var remainder: UInt32 = 0
            for i in limbs.indices {
                let value = (remainder << 8) | limbs[i]
                limbs[i] = value / 10
                remainder = value % 10
            }
            digits.append(Character(String(remainder)))
            while let first = limbs.first, first == 0, limbs.count > 1 { limbs.removeFirst() }
        }
        if digits.isEmpty { digits = ["1"] }
        return String(digits.reversed())
    }
}

// MARK: - Concatenations (PS3.3 C.7.6.16.2.2.4)

/// Splits one multi-frame instance into concatenation parts and reassembles them.
/// Mirrors DCMTK's `ConcatenationCreator` / `ConcatenationLoader`.
public enum MultiframeConcatenation {

    /// IODs whose definition forbids concatenations.
    public static let refusedSOPClasses: Set<String> = [
        MultiframeSOPClassMap.UID.ophthalmicTomography,
    ]

    public struct Part: Sendable, Equatable {
        public let index: Int          // 0-based
        public let total: Int
        public let frames: Range<Int>  // 0-based source frame indices
    }

    public static func parts(frameCount: Int, framesPerInstance: Int) -> [Part] {
        let n = max(1, framesPerInstance)
        let total = (frameCount + n - 1) / n
        return (0..<total).map { i in
            Part(index: i, total: total, frames: (i * n)..<min(frameCount, (i + 1) * n))
        }
    }

    /// Attributes that identify a concatenation part.
    public static let partTags: [Tag] = [
        .concatenationUID, .inConcatenationNumber, .inConcatenationTotalNumber,
        .concatenationFrameOffsetNumber, .sopInstanceUIDOfConcatenationSource,
    ]

    /// The data set of one part: the source's attributes, the part's Per-frame
    /// items, its legacy vectors sliced to the range, and the concatenation
    /// bookkeeping. Pixel data and SOP Instance UID are left to the caller.
    public static func partDataSet(
        source: DataSet,
        part: Part,
        concatenationUID: String,
        vectorKind: MultiframeSOPClassMap.LegacyVectorKind
    ) -> DataSet {
        var ds = source
        ds[.pixelData] = nil
        ds[.extendedOffsetTable] = nil
        ds[.extendedOffsetTableLengths] = nil

        if let items = source[.perFrameFunctionalGroupsSequence]?.sequenceItems {
            // Slice only what the source actually has: a short (malformed) sequence
            // must not survive at full length in a part that claims fewer frames.
            let upper = min(items.count, part.frames.upperBound)
            let lower = min(part.frames.lowerBound, upper)
            let slice = Array(items[lower..<upper])
            if slice.isEmpty {
                ds[.perFrameFunctionalGroupsSequence] = nil
            } else {
                ds.setSequence(slice, for: .perFrameFunctionalGroupsSequence)
            }
        }
        LegacyVectorResolver.resolve(&ds, frames: part.frames, kind: vectorKind, mode: .sameClass)

        ds.setString("\(part.frames.count)", for: .numberOfFrames, vr: .IS)
        ds.setString(concatenationUID, for: .concatenationUID, vr: .UI)
        ds.setUInt16(UInt16(part.index + 1), for: .inConcatenationNumber)
        ds.setUInt16(UInt16(part.total), for: .inConcatenationTotalNumber)
        ds.setUInt32(UInt32(part.frames.lowerBound), for: .concatenationFrameOffsetNumber)
        if let sourceUID = source.string(for: .sopInstanceUID).map(MultiframeSOPClassMap.normalize) {
            ds.setString(sourceUID, for: .sopInstanceUIDOfConcatenationSource, vr: .UI)
        }
        return ds
    }

    public static func isPart(_ ds: DataSet) -> Bool {
        !(ds.string(for: .concatenationUID)?.trimmingCharacters(in: CharacterSet(charactersIn: "\0 ")).isEmpty ?? true)
    }

    public enum ReassemblyError: Error, CustomStringConvertible {
        case mixedConcatenations(expected: String, found: String)
        case missingPart(number: Int, total: Int)
        case inconsistentPart(reason: String)

        public var description: String {
            switch self {
            case .mixedConcatenations(let e, let f): return "Inputs belong to different concatenations (\(e) vs \(f))"
            case .missingPart(let n, let t): return "Concatenation part \(n) of \(t) is missing"
            case .inconsistentPart(let reason): return "Inconsistent concatenation part: \(reason)"
            }
        }
    }

    public struct Reassembly {
        /// Merged data set without pixel data.
        public var dataSet: DataSet
        /// Input indices in In-concatenation Number order.
        public var partOrder: [Int]
        public var frameCount: Int
        public var concatenationUID: String
    }

    /// Reassembles concatenation parts (any input order) into one instance:
    /// Per-frame items and legacy vectors are concatenated, NumberOfFrames summed,
    /// the source SOP Instance UID restored and the part bookkeeping removed.
    public static func reassemble(parts: [DataSet]) throws -> Reassembly {
        guard !parts.isEmpty else { throw ReassemblyError.inconsistentPart(reason: "no parts") }
        let uids = parts.map { MultiframeSOPClassMap.normalize($0.string(for: .concatenationUID) ?? "") }
        for uid in uids.dropFirst() where uid != uids[0] {
            throw ReassemblyError.mixedConcatenations(expected: uids[0], found: uid)
        }
        let numbers = parts.map { Int($0.uint16(for: .inConcatenationNumber) ?? 0) }
        let order = parts.indices.sorted { numbers[$0] < numbers[$1] }
        let total = Int(parts[order[0]].uint16(for: .inConcatenationTotalNumber) ?? UInt16(parts.count))
        for (rank, idx) in order.enumerated() where numbers[idx] != rank + 1 {
            throw ReassemblyError.missingPart(number: rank + 1, total: total)
        }
        for tag in [Tag.rows, .columns, .bitsAllocated, .samplesPerPixel, .photometricInterpretation, .sopClassUID] {
            let expected = parts[order[0]].string(for: tag)
            for idx in order.dropFirst() where parts[idx].string(for: tag) != expected {
                throw ReassemblyError.inconsistentPart(reason: "\(tag) differs between parts")
            }
        }

        var merged = parts[order[0]]
        var perFrame: [SequenceItem] = []
        var frameTimes: [String] = []
        var nmVectors: [Tag: [UInt16]] = [:]
        var frameCount = 0
        for idx in order {
            let part = parts[idx]
            let n = part.numberOfFrames ?? 1
            frameCount += n
            if let items = part[.perFrameFunctionalGroupsSequence]?.sequenceItems { perFrame.append(contentsOf: items) }
            if let v = part.strings(for: .frameTimeVector) { frameTimes.append(contentsOf: v) }
            for tag in LegacyVectorResolver.nuclearMedicineVectors {
                if let v = part.uint16s(for: tag) { nmVectors[tag, default: []].append(contentsOf: v) }
            }
        }
        if !perFrame.isEmpty { merged.setSequence(perFrame, for: .perFrameFunctionalGroupsSequence) }
        if !frameTimes.isEmpty, frameTimes.count == frameCount { merged.setStrings(frameTimes, for: .frameTimeVector, vr: .DS) }
        for (tag, values) in nmVectors where values.count == frameCount { merged.setUInt16s(values, for: tag) }
        merged.setString("\(frameCount)", for: .numberOfFrames, vr: .IS)
        if let sourceUID = merged.string(for: .sopInstanceUIDOfConcatenationSource).map(MultiframeSOPClassMap.normalize), !sourceUID.isEmpty {
            merged.setString(sourceUID, for: .sopInstanceUID, vr: .UI)
        }
        for tag in partTags { merged[tag] = nil }
        merged[.pixelData] = nil
        return Reassembly(dataSet: merged, partOrder: order, frameCount: frameCount, concatenationUID: uids[0])
    }
}

// MARK: - Provenance

/// Rewrites references to multi-frame instances so they point at the
/// single-frame instances a split produces (dcm4che `adjustReferencedImages`):
/// an item naming a supported multi-frame SOP class together with Referenced
/// Frame Number becomes one item per frame, each carrying the derived UID and
/// the split target's SOP class.
public enum ProvenanceRewriter {

    public static let referenceSequences: [Tag] = [.referencedImageSequence, .sourceImageSequence]

    public static func expandFrameReferences(in ds: inout DataSet) {
        for tag in referenceSequences {
            guard let items = ds[tag]?.sequenceItems, !items.isEmpty else { continue }
            var changed = false
            var rewritten: [SequenceItem] = []
            for item in items {
                guard let classUID = item.string(for: .referencedSOPClassUID).map(MultiframeSOPClassMap.normalize),
                      let entry = MultiframeSOPClassMap.entry(for: classUID),
                      let instanceUID = item.string(for: .referencedSOPInstanceUID).map(MultiframeSOPClassMap.normalize),
                      let frames = item.strings(for: .referencedFrameNumber)?.compactMap({ Int($0.trimmingCharacters(in: .whitespaces)) }),
                      !frames.isEmpty else {
                    rewritten.append(item)
                    continue
                }
                let targetClass: String
                if case .convert(let uid) = entry.splitTarget { targetClass = uid } else { targetClass = classUID }
                for frame in frames {
                    var elements = item.allElements.filter { $0.tag != .referencedFrameNumber }
                    elements.removeAll { $0.tag == .referencedSOPClassUID || $0.tag == .referencedSOPInstanceUID }
                    elements.append(DataElement.string(tag: .referencedSOPClassUID, vr: .UI, value: targetClass))
                    elements.append(DataElement.string(tag: .referencedSOPInstanceUID, vr: .UI,
                                                       value: MultiframeInstanceUIDs.derived(from: instanceUID, frame: frame - 1)))
                    rewritten.append(SequenceItem(elements: elements))
                }
                changed = true
            }
            if changed { ds.setSequence(rewritten, for: tag) }
        }
    }
}
