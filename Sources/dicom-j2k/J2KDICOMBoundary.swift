// NEMA-verified: 2026a, checked 2026-10-01 — DICOM boundary of the J2K re-encodes: frame → fragment mapping per PS3.5 2026a A.4 / A.4.4 (Extended and Basic Offset Table, one fragment per frame, single frame, SOC-delimited frames); Photometric Interpretation after encode per PS3.5 2026a 8.2.4 / 8.2.14 and Tables 8.2.4-1 / 8.2.14-1 (MCT 1 → YBR_RCT (5-3) or YBR_ICT (9-7), Planar Configuration 0); lossy provenance per PS3.3 2026a C.7.6.1.1.5, C.7.6.1.1.5.1 (ISO_15444_1 / ISO_15444_15 via TransferSyntax), C.7.6.1.1.5.2; derived images per C.7.6.1.1.2 (Image Type Value 1 DERIVED, new SOP Instance UID, PS3.10 Table 7.1-1 (0002,0003)); ROI geometry per C.7.6.2.1.1 and C.7.6.16 (Number of Frames, Per-frame Functional Groups); .202 RPCL / ≤64 base resolution / TLM per PS3.5 2026a 10.18.1
import Foundation
import DICOMCore
import DICOMKit

/// The DICOM side of every dicom-j2k re-encode. The codestream itself (ISO/IEC 15444-1 / -15)
/// is out of scope here; what DICOM governs is how a frame is found in the encapsulated
/// fragments and which Data Elements must change when a new codestream is written.
enum J2KDICOMBoundary {

    // MARK: - Frames (PS3.5 A.4, A.4.4)

    enum FrameError: Error, CustomStringConvertible {
        case notEncapsulated
        case unmappable(frames: Int, fragments: Int)
        case frameOutOfRange(Int, Int)

        var description: String {
            switch self {
            case .notEncapsulated:
                return "Pixel Data (7FE0,0010) is not encapsulated."
            case .unmappable(let frames, let fragments):
                return "Cannot map \(fragments) fragments to \(frames) frames: the Basic / Extended "
                    + "Offset Table is absent or inconsistent and the fragments do not start "
                    + "with a JPEG 2000 SOC marker (PS3.5 A.4)."
            case .frameOutOfRange(let frame, let count):
                return "Frame number \(frame + 1) is out of range (Number of Frames is \(count); the first Frame is Frame number 1, PS3.3 Table 10-3)."
            }
        }
    }

    /// Splits encapsulated JPEG 2000 / HTJ2K Pixel Data into one codestream per frame.
    ///
    /// PS3.5 2026a A.4.4: "the encoded data from one Frame may span multiple Fragments for
    /// JPEG 2000 Transfer Syntaxes"; 8.2: an implementation that does not support such
    /// fragmentation does not conform. Resolution order: Extended Offset Table (7FE0,0001),
    /// Basic Offset Table, one fragment per frame, single frame (all fragments), and as a last
    /// resort a new frame at every fragment that starts with the SOC marker (FF4F).
    static func frameCodestreams(fragments: [Data], basicOffsetTable: [UInt32],
                                 extendedOffsetTable: [UInt64]?, numberOfFrames: Int) throws -> [Data] {
        guard !fragments.isEmpty else { throw FrameError.notEncapsulated }
        let frames = max(1, numberOfFrames)

        var groups: [[Int]]?
        if let eot = extendedOffsetTable, !eot.isEmpty {
            groups = group(fragments: fragments, startOffsets: eot.map { Int($0) }, frames: frames)
        } else if !basicOffsetTable.isEmpty {
            groups = group(fragments: fragments, startOffsets: basicOffsetTable.map { Int($0) }, frames: frames)
        } else if fragments.count == frames {
            groups = (0..<frames).map { [$0] }
        } else if frames == 1 {
            groups = [Array(fragments.indices)]
        } else {
            // No table, more fragments than frames: a frame starts at each SOC.
            var bySOC: [[Int]] = []
            for (i, fragment) in fragments.enumerated() {
                if startsWithSOC(fragment) || bySOC.isEmpty {
                    bySOC.append([i])
                } else {
                    bySOC[bySOC.count - 1].append(i)
                }
            }
            groups = bySOC.count == frames ? bySOC : nil
        }
        guard let map = groups else {
            throw FrameError.unmappable(frames: frames, fragments: fragments.count)
        }
        return map.map { indices in
            if indices.count == 1 { return fragments[indices[0]] }
            var combined = Data()
            for i in indices { combined.append(fragments[i]) }
            return combined
        }
    }

    /// Offsets are to the first byte of each frame's first Item Tag, measured from the first
    /// Item Tag after the Basic Offset Table Item; every item adds an 8-byte header (PS3.5 A.4).
    private static func group(fragments: [Data], startOffsets: [Int], frames: Int) -> [[Int]]? {
        guard startOffsets.count >= frames, startOffsets.first == 0 else { return nil }
        let offsets = Array(startOffsets.prefix(frames))
        var itemStarts: [Int] = []
        var cursor = 0
        for fragment in fragments {
            itemStarts.append(cursor)
            cursor += 8 + fragment.count
        }
        var map: [[Int]] = []
        var next = 0
        for (f, start) in offsets.enumerated() {
            if f > 0 && start <= offsets[f - 1] { return nil }
            guard next < itemStarts.count, itemStarts[next] == start else { return nil }
            let end = f + 1 < offsets.count ? offsets[f + 1] : Int.max
            var indices: [Int] = []
            while next < itemStarts.count, itemStarts[next] < end {
                indices.append(next)
                next += 1
            }
            map.append(indices)
        }
        return next == fragments.count ? map : nil
    }

    static func startsWithSOC(_ data: Data) -> Bool {
        data.count >= 2 && data[data.startIndex] == 0xFF && data[data.startIndex + 1] == 0x4F
    }

    /// All frame codestreams of a DICOM file.
    static func frameCodestreams(of file: DICOMFile) throws -> [Data] {
        guard let element = file.dataSet[.pixelData],
              let fragments = element.encapsulatedFragments, !fragments.isEmpty else {
            throw FrameError.notEncapsulated
        }
        return try frameCodestreams(
            fragments: fragments,
            basicOffsetTable: element.encapsulatedOffsetTable ?? [],
            extendedOffsetTable: extendedOffsetTable(of: file.dataSet),
            numberOfFrames: numberOfFrames(of: file.dataSet))
    }

    /// One frame's codestream (0-based index).
    static func frameCodestream(of file: DICOMFile, frame: Int) throws -> Data {
        let all = try frameCodestreams(of: file)
        guard frame >= 0, frame < all.count else {
            throw FrameError.frameOutOfRange(frame, all.count)
        }
        return all[frame]
    }

    /// Number of Frames (0028,0008), IS; 1 when absent.
    static func numberOfFrames(of dataSet: DataSet) -> Int {
        guard let s = dataSet.string(for: .numberOfFrames)?.trimmingCharacters(in: .whitespaces),
              let n = Int(s), n > 0 else { return 1 }
        return n
    }

    /// Extended Offset Table (7FE0,0001), OV: 64-bit little-endian offsets.
    static func extendedOffsetTable(of dataSet: DataSet) -> [UInt64]? {
        guard let element = dataSet[.extendedOffsetTable], !element.valueData.isEmpty,
              element.valueData.count % 8 == 0 else { return nil }
        let bytes = [UInt8](element.valueData)
        return stride(from: 0, to: bytes.count, by: 8).map { i in
            (0..<8).reduce(UInt64(0)) { $0 | (UInt64(bytes[i + $1]) << (8 * UInt64($1))) }
        }
    }

    // MARK: - Codestream facts the Data Set must agree with (PS3.5 8.2.4, 8.2.14, 10.18.1)

    struct CodestreamFacts: Equatable {
        /// SGcod progression order: 0 LRCP, 1 RLCP, 2 RPCL, 3 PCRL, 4 CPRL.
        var progressionOrder: UInt8
        /// SGcod multiple component transformation: 1 = RCT/ICT applied.
        var multipleComponentTransform: UInt8
        /// SPcod number of decomposition levels.
        var decompositionLevels: Int
        /// SPcod transformation: 1 = 5-3 reversible, 0 = 9-7 irreversible.
        var reversibleWavelet: Bool
        /// A TLM marker segment (FF55) is present in the main header.
        var hasTLM: Bool
    }

    /// Reads the main-header COD and TLM markers (marker segments up to the first SOT/SOD).
    static func codestreamFacts(_ cs: Data) -> CodestreamFacts? {
        let b = [UInt8](cs)
        guard b.count >= 4, b[0] == 0xFF, b[1] == 0x4F else { return nil }
        var i = 2
        var facts: CodestreamFacts?
        var tlm = false
        while i + 4 <= b.count, b[i] == 0xFF {
            let marker = b[i + 1]
            if marker == 0x90 || marker == 0x93 { break } // SOT / SOD: end of main header
            let length = Int(b[i + 2]) << 8 | Int(b[i + 3])
            if marker == 0x55 { tlm = true }
            if marker == 0x52, i + 13 < b.count {           // COD
                facts = CodestreamFacts(
                    progressionOrder: b[i + 5],
                    multipleComponentTransform: b[i + 8],
                    decompositionLevels: Int(b[i + 9]),
                    reversibleWavelet: b[i + 13] == 1,
                    hasTLM: false)
            }
            i += 2 + length
        }
        facts?.hasTLM = tlm
        return facts
    }

    /// Photometric Interpretation (0028,0004) for a newly written codestream.
    ///
    /// PS3.5 2026a 8.2.4 / 8.2.14: with the Part 1 reversible multi-component transformation
    /// the value shall be YBR_RCT, with the irreversible one YBR_ICT; without one the
    /// components are as encoded, so a source YBR_RCT / YBR_ICT (decoded to RGB) becomes RGB.
    static func photometricInterpretation(current: String?, samplesPerPixel: Int,
                                          facts: CodestreamFacts?) -> String? {
        guard samplesPerPixel == 3, let facts else { return current }
        if facts.multipleComponentTransform == 1 {
            return facts.reversibleWavelet ? "YBR_RCT" : "YBR_ICT"
        }
        let pi = current?.trimmingCharacters(in: .whitespaces).uppercased()
        if pi == "YBR_RCT" || pi == "YBR_ICT" { return "RGB" }
        return current
    }

    /// PS3.5 2026a 10.18.1: decompositions sufficient for the base resolution to be ≤ 64.
    static func minimumDecompositionLevelsForRPCL(rows: Int, columns: Int) -> Int {
        var levels = 0
        var size = max(rows, columns)
        while size > 64 {
            size = (size + 1) / 2
            levels += 1
        }
        return levels
    }

    /// The PS3.5 10.18.1 requirements a `.202` codestream misses (empty when it conforms).
    static func rpclViolations(_ facts: CodestreamFacts?, rows: Int, columns: Int) -> [String] {
        guard let facts else { return ["no COD marker segment found"] }
        var out: [String] = []
        if facts.progressionOrder != 2 { out.append("progression order is not RPCL") }
        let need = minimumDecompositionLevelsForRPCL(rows: rows, columns: columns)
        if facts.decompositionLevels < need {
            out.append("\(facts.decompositionLevels) decomposition levels; \(need) needed for a base resolution ≤ 64")
        }
        if !facts.hasTLM { out.append("no TLM marker segment") }
        return out
    }

    // MARK: - Data Set updates after a new codestream (PS3.3 C.7.6.1.1.2, C.7.6.1.1.5, C.7.6.3)

    /// Sets Photometric Interpretation from the first written codestream and Planar
    /// Configuration 0 for colour (PS3.5 8.2.4: "it shall be set to 0").
    static func applyPixelModule(to dataSet: inout DataSet, firstCodestream: Data) {
        let spp = Int(dataSet.uint16(for: .samplesPerPixel) ?? 1)
        let current = dataSet.string(for: .photometricInterpretation)
        if let pi = photometricInterpretation(current: current, samplesPerPixel: spp,
                                              facts: codestreamFacts(firstCodestream)),
           pi != current?.trimmingCharacters(in: .whitespaces) {
            dataSet.setString(pi, for: .photometricInterpretation, vr: .CS)
        }
        if spp > 1 {
            dataSet.setUInt16(0, for: .planarConfiguration)
        }
    }

    /// Records an irreversible encode (PS3.3 2026a C.7.6.1.1.5): Lossy Image Compression "01"
    /// (never reset), one more Ratio / Method pair (C.7.6.1.1.5.1-2, parallel VM 1-n), the
    /// ratio also in Derivation Description, Image Type Value 1 DERIVED and a new SOP
    /// Instance UID ("if the predecessor was a DICOM image").
    static func applyLossyCompression(to dataSet: inout DataSet, meta: inout DataSet,
                                      method: String, uncompressedBytes: Int, compressedBytes: Int) {
        dataSet.setString("01", for: .lossyImageCompression, vr: .CS)
        let ratio = Double(uncompressedBytes) / Double(max(1, compressedBytes))
        var ratios = dataSet.strings(for: .lossyImageCompressionRatio) ?? []
        var methods = dataSet.strings(for: .lossyImageCompressionMethod) ?? []
        let paired = min(ratios.count, methods.count)
        ratios = Array(ratios.prefix(paired)) + [DICOMDecimalString(value: ratio).dicomString]
        methods = Array(methods.prefix(paired)) + [method]
        dataSet.setStrings(ratios, for: .lossyImageCompressionRatio, vr: .DS)
        dataSet.setStrings(methods, for: .lossyImageCompressionMethod, vr: .CS)
        appendDerivationDescription(
            String(format: "Lossy compression %@ %.1f:1", method, ratio), to: &dataSet)
        markDerived(&dataSet, meta: &meta)
    }

    /// Image Type (0008,0008) Value 1 → DERIVED when present, and a new SOP Instance UID in
    /// the Data Set and in Media Storage SOP Instance UID (0002,0003) (PS3.3 C.7.6.1.1.2;
    /// PS3.10 Table 7.1-1). Returns the new UID.
    @discardableResult
    static func markDerived(_ dataSet: inout DataSet, meta: inout DataSet) -> String {
        var imageType = dataSet.strings(for: .imageType) ?? []
        if !imageType.isEmpty, imageType[0].trimmingCharacters(in: .whitespaces).uppercased() == "ORIGINAL" {
            imageType[0] = "DERIVED"
            dataSet.setStrings(imageType, for: .imageType, vr: .CS)
        }
        let uid = UIDGenerator.generateSOPInstanceUID().value
        dataSet.setString(uid, for: .sopInstanceUID, vr: .UI)
        meta.setString(uid, for: .mediaStorageSOPInstanceUID, vr: .UI)
        invalidateGroupLength(&meta)
        return uid
    }

    /// Drops File Meta Information Group Length (0002,0000) after a meta element changed, so
    /// `DICOMFile.write()` recomputes it (PS3.10 Table 7.1-1: Type 1, the byte count of the
    /// rest of group 0002). A stale value makes the file unreadable to strict parsers.
    static func invalidateGroupLength(_ meta: inout DataSet) {
        meta.remove(tag: .fileMetaInformationGroupLength)
    }

    /// Derivation Description (0008,2111), ST (≤ 1024 characters).
    static func appendDerivationDescription(_ text: String, to dataSet: inout DataSet) {
        let existing = dataSet.string(for: .derivationDescription)?
            .trimmingCharacters(in: .whitespaces) ?? ""
        let joined = existing.isEmpty ? text : existing + "; " + text
        dataSet.setString(String(joined.prefix(1024)), for: .derivationDescription, vr: .ST)
    }

    /// Bytes of the native Pixel Data the codestreams represent (Rows × Columns × Samples ×
    /// Bits Allocated / 8 × frames), for the measured compression ratio (C.7.6.1.1.5.2).
    static func uncompressedByteCount(of dataSet: DataSet, frames: Int) -> Int {
        let rows = Int(dataSet.uint16(for: .rows) ?? 0)
        let cols = Int(dataSet.uint16(for: .columns) ?? 0)
        let spp = Int(dataSet.uint16(for: .samplesPerPixel) ?? 1)
        let bitsAllocated = Int(dataSet.uint16(for: .bitsAllocated) ?? 16)
        return rows * cols * spp * max(1, bitsAllocated / 8) * frames
    }

    /// Writes the new encapsulated Pixel Data: one fragment per frame (required for HTJ2K,
    /// PS3.5 A.4.4) and an empty Basic Offset Table; an Extended Offset Table that described
    /// the old fragments is removed.
    static func setEncapsulatedPixelData(_ codestreams: [Data], in dataSet: inout DataSet) {
        dataSet[.pixelData] = DataElement(
            tag: .pixelData, vr: .OB, length: 0xFFFFFFFF, valueData: Data(),
            encapsulatedFragments: codestreams.map { $0.count % 2 == 0 ? $0 : $0 + Data([0]) },
            encapsulatedOffsetTable: [])
        dataSet.remove(tag: .extendedOffsetTable)
        dataSet.remove(tag: .extendedOffsetTableLengths)
    }

    // MARK: - ROI geometry (PS3.3 C.7.6.2.1.1, C.7.6.16)

    /// Image Position (Patient) of the pixel at (column x, row y): IPP + x·Δcol·rowDir +
    /// y·Δrow·colDir, where Image Orientation (Patient) is rowDir\colDir and Pixel Spacing is
    /// row spacing\column spacing (C.7.6.2.1.1, 10.7.1.3).
    static func shiftedPosition(ipp: [Double], iop: [Double], spacing: [Double], x: Int, y: Int) -> [Double]? {
        guard ipp.count == 3, iop.count == 6, spacing.count == 2 else { return nil }
        return (0..<3).map { k in
            ipp[k] + Double(x) * spacing[1] * iop[k] + Double(y) * spacing[0] * iop[3 + k]
        }
    }

    static func decimals(_ values: [Double]) -> [String] {
        values.map { DICOMDecimalString(value: $0).dicomString }
    }

    private static func doubles(_ item: SequenceItem?, _ tag: Tag) -> [Double]? {
        guard let s = item?.strings(for: tag) else { return nil }
        let v = s.compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
        return v.count == s.count ? v : nil
    }

    private static func doubles(_ dataSet: DataSet, _ tag: Tag) -> [Double]? {
        guard let s = dataSet.strings(for: tag) else { return nil }
        let v = s.compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
        return v.count == s.count ? v : nil
    }

    /// Turns the data set into a single-frame crop of frame `frame` at (x, y): Rows / Columns,
    /// Number of Frames 1, only that frame's Per-frame Functional Groups Sequence Item, and the
    /// Image Position (Patient) moved to the crop origin (top level and in the Plane Position
    /// Sequence of the kept item).
    static func applyCrop(to dataSet: inout DataSet, frame: Int, x: Int, y: Int, width: Int, height: Int) {
        dataSet.setUInt16(UInt16(height), for: .rows)
        dataSet.setUInt16(UInt16(width), for: .columns)
        if dataSet[.numberOfFrames] != nil {
            dataSet.setString("1", for: .numberOfFrames, vr: .IS)
        }

        // Classic Image Plane Module.
        if let ipp = doubles(dataSet, .imagePositionPatient),
           let iop = doubles(dataSet, .imageOrientationPatient),
           let ps = doubles(dataSet, .pixelSpacing),
           let moved = shiftedPosition(ipp: ipp, iop: iop, spacing: ps, x: x, y: y) {
            dataSet.setStrings(decimals(moved), for: .imagePositionPatient, vr: .DS)
        }

        // Enhanced multi-frame: keep the selected frame's item only.
        guard let perFrame = dataSet.sequence(for: .perFrameFunctionalGroupsSequence),
              frame < perFrame.count else { return }
        let shared = dataSet.firstSequenceItem(for: .sharedFunctionalGroupsSequence)
        var item = perFrame[frame]
        func nested(_ seq: Tag, _ attr: Tag) -> [Double]? {
            doubles(item[seq]?.sequenceItems?.first, attr)
                ?? doubles(shared?[seq]?.sequenceItems?.first, attr)
        }
        if let positionItem = item[.planePositionSequence]?.sequenceItems?.first,
           let ipp = doubles(positionItem, .imagePositionPatient),
           let iop = nested(.planeOrientationSequence, .imageOrientationPatient),
           let ps = nested(.pixelMeasuresSequence, .pixelSpacing),
           let moved = shiftedPosition(ipp: ipp, iop: iop, spacing: ps, x: x, y: y) {
            var tmp = DataSet(elements: Array(positionItem.elements.values))
            tmp.setStrings(decimals(moved), for: .imagePositionPatient, vr: .DS)
            var holder = DataSet()
            holder.setSequence([SequenceItem(elements: tmp.allElements)], for: .planePositionSequence)
            var elements = item.elements
            elements[.planePositionSequence] = holder[.planePositionSequence]
            item = SequenceItem(elements: elements)
        }
        dataSet.setSequence([item], for: .perFrameFunctionalGroupsSequence)
    }
}
