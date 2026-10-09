// NEMA-verified: 2026a, checked 2026-09-25 — implements ISO/IEC 15444, not DICOM. The one PS3.5 citation was corrected to A.4.4, which in 2026a defines all five JPEG 2000 and HTJ2K syntaxes. C1 classification confirmed.

import Foundation

/// Read-only inspection of a JPEG 2000 codestream's headers.
///
/// DICOMKit uses this to answer questions the pinned J2KSwift decoder cannot
/// answer for itself. J2KSwift's marker loop (`J2KDecoderPipeline`) dispatches on
/// SIZ/COD/QCD/COM/SOT/EOC and *skips every other marker segment*, so a codestream
/// carrying JPEG 2000 Part 2 extensions decodes as though those extensions were
/// absent — silently, and with wrong pixels. Scanning the headers ourselves lets the
/// codec refuse such a frame instead of returning a plausible-looking image.
public enum J2KCodestreamInspector {

    // MARK: - Marker codes

    // ISO/IEC 15444-1 (Part 1) delimiting / header markers.
    private static let soc: UInt16 = 0xFF4F  // Start of codestream
    private static let sot: UInt16 = 0xFF90  // Start of tile-part
    private static let sod: UInt16 = 0xFF93  // Start of data
    private static let eoc: UInt16 = 0xFFD9  // End of codestream
    private static let siz: UInt16 = 0xFF51  // Image and tile size
    private static let cod: UInt16 = 0xFF52  // Coding style default
    private static let coc: UInt16 = 0xFF53  // Coding style component

    /// ISO/IEC 15444-2 (Part 2) multi-component transform marker segments.
    ///
    /// Values are the **standard** ones, cross-checked against the OpenJPEG
    /// reference implementation (`j2k.h`: `J2K_MS_MCT 0xff74`, `J2K_MS_MCC 0xff75`,
    /// `J2K_MS_MCO 0xff77`). Note that J2KSwift's own `J2KMarker` enum assigns these
    /// three names to different codes (`mct = 0xFF75`, `mco = 0xFF76`,
    /// `mcc = 0xFF77`); that mapping is unused by its pipelines and must **not** be
    /// mirrored here — this scanner exists to recognise codestreams produced by
    /// conformant third-party encoders (Kakadu, OpenJPEG, …).
    public enum Part2MultiComponentMarker: UInt16, CaseIterable, Sendable {
        /// Multiple component transformation — defines a transform array.
        case mct = 0xFF74
        /// Multiple component collection — groups the components a transform covers.
        case mcc = 0xFF75
        /// Multiple component transform ordering — the order transforms are applied.
        case mco = 0xFF77

        public var name: String {
            switch self {
            case .mct: return "MCT"
            case .mcc: return "MCC"
            case .mco: return "MCO"
            }
        }
    }

    // MARK: - Public API

    /// The Part 2 multi-component transform markers present in `data`'s headers, in
    /// the order first encountered (de-duplicated). Empty when the codestream is
    /// plain Part 1 / HTJ2K, when it carries no such markers, or when `data` is not
    /// a codestream this scanner recognises.
    ///
    /// Scanning is confined to the main header and each tile-part header; packet
    /// bodies are skipped via `Psot`. A conformant encoder only writes MCT/MCC/MCO
    /// when a multi-component transform is actually in force, so presence is
    /// sufficient grounds to treat the frame as un-decodable here.
    ///
    /// This never throws: a malformed or truncated codestream simply yields whatever
    /// was found before the scan ran out of well-formed input. Rejecting malformed
    /// input is the decoder's job, not this scanner's.
    public static func part2MultiComponentMarkers(in data: Data) -> [Part2MultiComponentMarker] {
        guard let codestream = locateCodestream(in: data) else { return [] }
        return scanHeaders(codestream)
    }

    /// Whether `data` carries a Part 2 multi-component transform the pinned decoder
    /// would ignore rather than invert.
    public static func containsPart2MultiComponentTransform(in data: Data) -> Bool {
        !part2MultiComponentMarkers(in: data).isEmpty
    }

    /// Whether any COD or COC marker segment in the main header or a tile-part
    /// header selects the irreversible 9/7 wavelet (ISO/IEC 15444-1 Table A.20:
    /// SPcod/SPcoc transformation byte 0; 1 is the reversible 5/3 filter).
    ///
    /// A lossless-only DICOM transfer syntax (PS3.5 2026a A.4.4: `…4.90`, `…4.201`
    /// and `…4.202`) promises exact reconstruction, which a 9/7 codestream cannot
    /// deliver, so the codec refuses such a frame instead of returning
    /// approximated samples. Rate truncation of a reversible codestream is not
    /// detectable from headers and is not claimed here.
    ///
    /// This never throws and returns `false` for malformed or truncated input;
    /// rejecting malformed input is the decoder's job.
    public static func usesIrreversibleWavelet(in data: Data) -> Bool {
        guard let codestream = locateCodestream(in: data) else { return false }
        var componentCount = 0
        var irreversible = false
        forEachHeaderSegment(in: codestream) { marker, offset, length in
            switch marker {
            case siz:
                // Lsiz(2) Rsiz(2) Xsiz…YTOsiz(8×4) Csiz(2): Csiz sits 38 bytes past the marker.
                if length >= 38, let csiz = readUInt16(codestream, at: offset + 38) {
                    componentCount = Int(csiz)
                }
            case cod:
                // Lcod(2) Scod(1) SGcod(4) SPcod: NL xcb ycb cbstyle transformation.
                if length >= 12, let transformation = readUInt8(codestream, at: offset + 13), transformation == 0 {
                    irreversible = true
                }
            case coc:
                // Lcoc(2) Ccoc(1 or 2, by Csiz) Scoc(1) SPcoc: NL xcb ycb cbstyle transformation.
                let componentIndexWidth = componentCount < 257 ? 1 : 2
                if length >= 8 + componentIndexWidth,
                   let transformation = readUInt8(codestream, at: offset + 9 + componentIndexWidth),
                   transformation == 0 {
                    irreversible = true
                }
            default:
                break
            }
        }
        return irreversible
    }

    // MARK: - HTJ2K Lossless RPCL (PS3.5 2026a 10.18.1)

    /// Main-header coding-style facts a DICOM Data Set or Transfer Syntax must agree with.
    public struct CodingStyle: Sendable, Equatable {
        /// SGcod progression order (ISO/IEC 15444-1 Table A.16): 0 LRCP, 1 RLCP, 2 RPCL, 3 PCRL, 4 CPRL.
        public var progressionOrder: UInt8
        /// SGcod number of quality layers.
        public var qualityLayers: Int
        /// SGcod multiple component transformation: 1 = RCT (5-3) or ICT (9-7) applied.
        public var multipleComponentTransform: UInt8
        /// SPcod number of decomposition levels.
        public var decompositionLevels: Int
        /// SPcod transformation: `true` for the reversible 5-3 filter, `false` for 9-7.
        public var reversibleWavelet: Bool
        /// Scod bit 0: precinct sizes are given (otherwise one maximal 2^15 precinct per band).
        public var userDefinedPrecincts: Bool
        /// A TLM marker segment (FF55) is present in the main header.
        public var hasTLM: Bool
        /// A POC marker segment (FF5F) is present in the main or a tile-part header.
        public var hasPOC: Bool
        /// A COD or COC marker segment overrides the main COD (COC anywhere, COD in a tile-part header).
        public var hasCodingStyleOverride: Bool
        /// Number of components (SIZ Csiz).
        public var componentCount: Int
        /// Reference grid size (SIZ Xsiz, Ysiz).
        public var gridWidth: Int
        public var gridHeight: Int
        /// Number of tile-parts.
        public var tilePartCount: Int
    }

    /// Reads the coding-style facts of a bare codestream (or of the `jp2c` box of a JP2 file).
    /// Returns `nil` when no SIZ or main-header COD marker segment is found.
    public static func codingStyle(in data: Data) -> CodingStyle? {
        guard let codestream = locateCodestream(in: data) else { return nil }
        var siz: (csiz: Int, width: Int, height: Int)?
        var cod: (scod: UInt8, prog: UInt8, layers: Int, mct: UInt8, levels: Int, reversible: Bool)?
        var tlm = false, poc = false, override = false
        var tileParts = 0
        var inTilePart = false
        forEachHeaderSegment(in: codestream) { marker, offset, length in
            switch marker {
            case Self.sot:
                tileParts += 1
                inTilePart = true
            case Self.siz:
                if length >= 38, let csiz = readUInt16(codestream, at: offset + 38),
                   let x = readUInt32(codestream, at: offset + 6), let y = readUInt32(codestream, at: offset + 10) {
                    siz = (Int(csiz), Int(x), Int(y))
                }
            case Self.cod:
                if inTilePart { override = true; break }
                // Lcod(2) Scod(1) SGcod: progression(1) layers(2) MCT(1); SPcod: NL xcb ycb style transformation.
                if length >= 12,
                   let scod = readUInt8(codestream, at: offset + 4),
                   let prog = readUInt8(codestream, at: offset + 5),
                   let layers = readUInt16(codestream, at: offset + 6),
                   let mct = readUInt8(codestream, at: offset + 8),
                   let levels = readUInt8(codestream, at: offset + 9),
                   let transformation = readUInt8(codestream, at: offset + 13) {
                    cod = (scod, prog, Int(layers), mct, Int(levels), transformation == 1)
                }
            case Self.coc:
                override = true
            case Self.tlm:
                if !inTilePart { tlm = true }
            case Self.poc:
                poc = true
            default:
                break
            }
        }
        guard let siz, let cod else { return nil }
        return CodingStyle(
            progressionOrder: cod.prog, qualityLayers: cod.layers, multipleComponentTransform: cod.mct,
            decompositionLevels: cod.levels, reversibleWavelet: cod.reversible,
            userDefinedPrecincts: cod.scod & 0x01 != 0, hasTLM: tlm, hasPOC: poc,
            hasCodingStyleOverride: override, componentCount: siz.csiz,
            gridWidth: siz.width, gridHeight: siz.height, tilePartCount: tileParts)
    }

    /// PS3.5 2026a 10.18.1: "The number of decompositions shall be sufficient for the width or
    /// height of the base resolution to be <= 64". Read strictly (both ≤ 64), this is the number
    /// of halvings that brings the larger dimension to 64 or less.
    public static func minimumDecompositionLevelsForRPCL(rows: Int, columns: Int) -> Int {
        var levels = 0
        var size = max(rows, columns)
        while size > 64 {
            size = (size + 1) / 2
            levels += 1
        }
        return levels
    }

    /// The PS3.5 2026a 10.18.1 requirements of HTJ2K Lossless RPCL (1.2.840.10008.1.2.4.202)
    /// that `data` misses: RPCL progression, enough decompositions for a base resolution ≤ 64,
    /// and a TLM marker segment. Empty when the codestream conforms.
    public static func htj2kRPCLViolations(in data: Data, rows: Int, columns: Int) -> [String] {
        guard let style = codingStyle(in: data) else { return ["no SIZ / COD marker segment found"] }
        var out: [String] = []
        if style.progressionOrder != 2 || style.hasPOC { out.append("progression order is not RPCL") }
        let need = minimumDecompositionLevelsForRPCL(rows: rows, columns: columns)
        if style.decompositionLevels < need {
            out.append("\(style.decompositionLevels) decomposition levels; \(need) needed for a base resolution ≤ 64")
        }
        if !style.hasTLM { out.append("no TLM marker segment") }
        return out
    }

    /// Brings a bare codestream to the PS3.5 2026a 10.18.1 marker requirements where that is
    /// possible without re-encoding, and returns it unchanged otherwise:
    ///
    /// - **Progression order.** When the packet sequence of the declared order is provably the
    ///   same as RPCL's, SGcod is set to RPCL (2). That holds for one quality layer, the default
    ///   (maximal, 2^15) precincts with a reference grid of at most 32768 × 32768 or a single
    ///   component, and no POC / COC / tile-part COD: each tile then has one precinct per
    ///   component and resolution, so every order emits the packets resolution by resolution,
    ///   component by component (ISO/IEC 15444-1 B.12.1). The codestream bytes after the main
    ///   header are not touched.
    /// - **TLM.** A TLM marker segment (ISO/IEC 15444-1 A.7.1) listing every tile-part's
    ///   index and length is inserted at the end of the main header.
    public static func conformingToHTJ2KRPCL(_ data: Data) -> Data {
        guard readUInt16(data, at: 0) == soc, let style = codingStyle(in: data) else { return data }
        var bytes = [UInt8](data)

        // 1. Relabel the progression order when the packet order is unchanged by it.
        let onePrecinctPerBand = !style.userDefinedPrecincts
            && (style.componentCount == 1 || (style.gridWidth <= 32768 && style.gridHeight <= 32768))
        if style.progressionOrder != 2, style.qualityLayers == 1, onePrecinctPerBand,
           !style.hasPOC, !style.hasCodingStyleOverride,
           let codOffset = mainHeaderSegmentOffset(bytes, marker: cod) {
            bytes[codOffset + 5] = 2
        }

        // 2. Insert TLM before the first SOT.
        guard !style.hasTLM, let tileParts = tilePartLengths(bytes), !tileParts.parts.isEmpty else {
            return Data(bytes)
        }
        let wideIndex = tileParts.parts.contains { $0.index > 0xFF }
        let entrySize = (wideIndex ? 2 : 1) + 4
        let perSegment = (0xFFFF - 4) / entrySize
        let chunks = stride(from: 0, to: tileParts.parts.count, by: perSegment).map {
            Array(tileParts.parts[$0..<min($0 + perSegment, tileParts.parts.count)])
        }
        guard chunks.count <= 256 else { return Data(bytes) }
        var tlmBytes: [UInt8] = []
        for (z, chunk) in chunks.enumerated() {
            let length = 4 + chunk.count * entrySize
            // Stlm: ST (bits 4-5) = 1 for 8-bit, 2 for 16-bit Ttlm; SP (bit 6) = 1 for 32-bit Ptlm.
            let stlm: UInt8 = (wideIndex ? 0x20 : 0x10) | 0x40
            tlmBytes += [0xFF, 0x55, UInt8(length >> 8), UInt8(length & 0xFF), UInt8(z), stlm]
            for part in chunk {
                if wideIndex { tlmBytes += [UInt8(part.index >> 8), UInt8(part.index & 0xFF)] }
                else { tlmBytes.append(UInt8(part.index)) }
                let l = UInt32(part.length)
                tlmBytes += [UInt8(l >> 24), UInt8((l >> 16) & 0xFF), UInt8((l >> 8) & 0xFF), UInt8(l & 0xFF)]
            }
        }
        bytes.insert(contentsOf: tlmBytes, at: tileParts.firstSOT)
        return Data(bytes)
    }

    private static let tlm: UInt16 = 0xFF55  // Tile-part lengths
    private static let poc: UInt16 = 0xFF5F  // Progression order change

    /// Offset of a main-header marker segment (before the first SOT).
    private static func mainHeaderSegmentOffset(_ bytes: [UInt8], marker: UInt16) -> Int? {
        var offset = 2
        while offset + 4 <= bytes.count, bytes[offset] == 0xFF {
            let m = UInt16(bytes[offset]) << 8 | UInt16(bytes[offset + 1])
            if m == sot || m == sod || m == eoc { return nil }
            if m == marker { return offset }
            let length = Int(bytes[offset + 2]) << 8 | Int(bytes[offset + 3])
            guard length >= 2 else { return nil }
            offset += 2 + length
        }
        return nil
    }

    /// The offset of the first SOT and each tile-part's (Isot, length from SOT to its end).
    /// `nil` when the tile-part chain is malformed.
    private static func tilePartLengths(_ bytes: [UInt8]) -> (firstSOT: Int, parts: [(index: Int, length: Int)])? {
        var offset = 2
        while offset + 4 <= bytes.count, bytes[offset] == 0xFF {
            let m = UInt16(bytes[offset]) << 8 | UInt16(bytes[offset + 1])
            if m == sot { break }
            if m == sod || m == eoc { return nil }
            let length = Int(bytes[offset + 2]) << 8 | Int(bytes[offset + 3])
            guard length >= 2 else { return nil }
            offset += 2 + length
        }
        let firstSOT = offset
        var parts: [(index: Int, length: Int)] = []
        // The codestream ends with EOC; a Psot of 0 runs to it.
        let end = bytes.count >= 2 && bytes[bytes.count - 2] == 0xFF && bytes[bytes.count - 1] == 0xD9
            ? bytes.count - 2 : bytes.count
        while offset + 12 <= end, bytes[offset] == 0xFF, bytes[offset + 1] == 0x90 {
            let isot = Int(bytes[offset + 4]) << 8 | Int(bytes[offset + 5])
            var psot = 0
            for k in 0..<4 { psot = psot << 8 | Int(bytes[offset + 6 + k]) }
            if psot == 0 { psot = end - offset }
            guard psot >= 14, offset + psot <= end else { return nil }
            parts.append((isot, psot))
            offset += psot
        }
        guard offset == end, !parts.isEmpty else { return nil }
        return (firstSOT, parts)
    }

    // MARK: - Container handling

    /// Returns the raw codestream range, unwrapping a JP2 container if present.
    ///
    /// DICOM encapsulates a bare codestream (starting at SOC), but JP2-boxed pixel
    /// data appears in the wild, so both are handled.
    private static func locateCodestream(in data: Data) -> Data? {
        if readUInt16(data, at: 0) == soc { return data }
        return extractJP2Codestream(from: data)
    }

    /// Minimal JP2 (ISO/IEC 15444-1 Annex I) box walk to find the `jp2c` payload.
    private static func extractJP2Codestream(from data: Data) -> Data? {
        let jp2cType: UInt32 = 0x6A70_3263  // 'jp2c'
        var offset = 0

        while offset + 8 <= data.count {
            guard let lengthField = readUInt32(data, at: offset),
                  let boxType = readUInt32(data, at: offset + 4) else { return nil }

            // LBox semantics: 1 → 64-bit XLBox follows; 0 → box runs to end of file.
            let contentStart: Int
            let boxEnd: Int
            switch lengthField {
            case 1:
                guard let xlBox = readUInt64(data, at: offset + 8) else { return nil }
                contentStart = offset + 16
                guard let end = checkedEnd(start: offset, length: xlBox, limit: data.count) else { return nil }
                boxEnd = end
            case 0:
                contentStart = offset + 8
                boxEnd = data.count
            default:
                contentStart = offset + 8
                guard let end = checkedEnd(start: offset, length: UInt64(lengthField), limit: data.count) else { return nil }
                boxEnd = end
            }

            guard contentStart <= boxEnd, contentStart <= data.count else { return nil }

            if boxType == jp2cType {
                return data.subdata(in: absolute(data, contentStart)..<absolute(data, boxEnd))
            }

            // Guard against a zero/!advancing length pinning the loop.
            guard boxEnd > offset else { return nil }
            offset = boxEnd
        }
        return nil
    }

    /// Validates `start + length` against `limit`, returning the absolute end offset.
    private static func checkedEnd(start: Int, length: UInt64, limit: Int) -> Int? {
        guard length >= 8, length <= UInt64(limit) else { return nil }
        let end = start + Int(length)
        guard end <= limit else { return nil }
        return end
    }

    // MARK: - Marker scan

    private static func scanHeaders(_ data: Data) -> [Part2MultiComponentMarker] {
        var found: [Part2MultiComponentMarker] = []
        forEachHeaderSegment(in: data) { marker, _, _ in
            // Keep scanning after a hit: reporting every marker present makes the
            // eventual error message specific rather than naming whichever came first.
            if let part2 = Part2MultiComponentMarker(rawValue: marker), !found.contains(part2) {
                found.append(part2)
            }
        }
        return found
    }

    /// Visits every marker segment of the main header and of each tile-part header
    /// as `(marker, offset of the marker, segment length field)`; packet bodies are
    /// skipped via `Psot`. SOT itself is visited; SOC, SOD and EOC are not.
    ///
    /// A well-formed header position always begins 0xFF..; anything else means the
    /// walk lost sync (truncated or malformed input) and it stops rather than guess.
    private static func forEachHeaderSegment(in data: Data, _ visit: (UInt16, Int, Int) -> Void) {
        var offset = 2  // Past SOC.

        while let marker = readUInt16(data, at: offset) {
            guard marker & 0xFF00 == 0xFF00 else { break }

            if marker == eoc || marker == sod { break }

            // Delimiting markers carry no length segment.
            if marker == soc {
                offset += 2
                continue
            }

            if marker == sot {
                // Walk the tile-part header (it may hold COD/COC/MCT… too), then hop
                // to the next tile-part via Psot.
                guard let next = walkTilePart(data, sotOffset: offset, visit) else { break }
                guard let next, next > offset else { break }
                offset = next
                continue
            }

            guard let segmentLength = readUInt16(data, at: offset + 2) else { break }
            // Lsiz-style length counts itself but not the 2-byte marker.
            guard segmentLength >= 2 else { break }
            visit(marker, offset, Int(segmentLength))
            offset += 2 + Int(segmentLength)
        }
    }

    /// Visits a single tile-part header and returns the offset of the next tile-part
    /// (`.some(nil)` when this tile-part runs to EOC, `nil` when SOT is malformed).
    private static func walkTilePart(
        _ data: Data,
        sotOffset: Int,
        _ visit: (UInt16, Int, Int) -> Void
    ) -> Int?? {
        // SOT: Lsot(2) Isot(2) Psot(4) TPsot(1) TNsot(1) — Psot spans SOT..tile end.
        guard let lsot = readUInt16(data, at: sotOffset + 2), lsot == 10,
              let psot = readUInt32(data, at: sotOffset + 6) else { return nil }
        visit(sot, sotOffset, Int(lsot))

        var offset = sotOffset + 2 + Int(lsot)

        // Walk the tile-part header up to SOD.
        while let marker = readUInt16(data, at: offset) {
            guard marker & 0xFF00 == 0xFF00 else { break }
            if marker == sod || marker == eoc { break }
            guard let segmentLength = readUInt16(data, at: offset + 2), segmentLength >= 2 else { break }
            visit(marker, offset, Int(segmentLength))
            offset += 2 + Int(segmentLength)
        }

        // Psot == 0 means the tile-part extends to EOC: nothing further to scan.
        guard psot != 0 else { return .some(nil) }
        let next = sotOffset + Int(psot)
        guard next <= data.count else { return .some(nil) }
        return .some(next)
    }

    // MARK: - Big-endian readers (offsets are relative to `data.startIndex`)

    private static func absolute(_ data: Data, _ offset: Int) -> Data.Index {
        data.index(data.startIndex, offsetBy: offset)
    }

    private static func readUInt8(_ data: Data, at offset: Int) -> UInt8? {
        guard offset >= 0, offset + 1 <= data.count else { return nil }
        return data[absolute(data, offset)]
    }

    private static func readUInt16(_ data: Data, at offset: Int) -> UInt16? {
        guard offset >= 0, offset + 2 <= data.count else { return nil }
        let i = absolute(data, offset)
        return UInt16(data[i]) << 8 | UInt16(data[data.index(after: i)])
    }

    private static func readUInt32(_ data: Data, at offset: Int) -> UInt32? {
        guard offset >= 0, offset + 4 <= data.count else { return nil }
        var value: UInt32 = 0
        for k in 0..<4 { value = value << 8 | UInt32(data[absolute(data, offset + k)]) }
        return value
    }

    private static func readUInt64(_ data: Data, at offset: Int) -> UInt64? {
        guard offset >= 0, offset + 8 <= data.count else { return nil }
        var value: UInt64 = 0
        for k in 0..<8 { value = value << 8 | UInt64(data[absolute(data, offset + k)]) }
        return value
    }
}
