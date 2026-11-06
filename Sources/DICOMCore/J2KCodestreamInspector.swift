// NEMA-verified: 2026a, checked 2026-09-25 — implements ISO/IEC 15444, not DICOM. The one PS3.5 citation was corrected to A.4.4, which in 2026a defines all five JPEG 2000 and HTJ2K syntaxes. C1 classification confirmed.

import Foundation
import SwiftJ2K

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

    // ISO/IEC 15444-1 (Part 1) & 15444-15 (Part 15) delimiting / header markers.
    private static let soc: UInt16 = 0xFF4F  // Start of codestream
    private static let cap: UInt16 = 0xFF50  // Extended capabilities (HTJ2K / Part 15)
    private static let sot: UInt16 = 0xFF90  // Start of tile-part
    private static let sod: UInt16 = 0xFF93  // Start of data
    private static let eoc: UInt16 = 0xFFD9  // End of codestream
    private static let siz: UInt16 = 0xFF51  // Image and tile size
    private static let cod: UInt16 = 0xFF52  // Coding style default
    private static let coc: UInt16 = 0xFF53  // Coding style component
    private static let cbd: UInt16 = 0xFF78  // Component bit depth definition (Part 2)

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

    // MARK: - Pre-Decode Image Header Inspection (SIZ + CAP)

    /// Per-component SIZ descriptor fields (`Ssiz_i`, `XRsiz_i`, `YRsiz_i`).
    public struct ComponentHeader: Sendable, Equatable {
        /// Sample precision in bits (`1...38`).
        public var bitDepth: Int
        /// Whether samples are signed (`Ssiz_i` bit 7 == 1).
        public var isSigned: Bool
        /// Horizontal sample separation (`XRsiz_i`).
        public var subsamplingX: Int
        /// Vertical sample separation (`YRsiz_i`).
        public var subsamplingY: Int
    }

    /// Main-header image geometry, component precisions, and capability marker presence.
    public struct ImageHeader: Sendable, Equatable {
        /// Effective image width (`Xsiz - XOsiz`).
        public var width: Int
        /// Effective image height (`Ysiz - YOsiz`).
        public var height: Int
        /// Component headers declared in `SIZ`.
        public var components: [ComponentHeader]
        /// Whether the main header carries a `CAP` (`0xFF50`) marker segment.
        public var hasCAPMarker: Bool
        /// Whether `CAP` (`0xFF50`) sets `Pcap^15` (`0x0002_0000`, ISO/IEC 15444-15 HTJ2K).
        public var hasPart15CAPMarker: Bool
        /// Whether `CAP` (`0xFF50`) sets `Pcap^2` (`0x4000_0000`, ISO/IEC 15444-2 extensions).
        public var hasPart2CAPMarker: Bool
        /// Reconstructed logical component bit depths declared in Part 2 `CBD` (`0xFF78`), if present.
        public var cbdComponents: [ComponentHeader]?

        /// Reconstructed logical component headers (`cbdComponents` when Part 2 `CBD` is present, otherwise `components`).
        public var logicalComponents: [ComponentHeader] {
            cbdComponents ?? components
        }

        public init(
            width: Int,
            height: Int,
            components: [ComponentHeader],
            hasCAPMarker: Bool,
            hasPart15CAPMarker: Bool? = nil,
            hasPart2CAPMarker: Bool = false,
            cbdComponents: [ComponentHeader]? = nil
        ) {
            self.width = width
            self.height = height
            self.components = components
            self.hasCAPMarker = hasCAPMarker
            self.hasPart15CAPMarker = hasPart15CAPMarker ?? hasCAPMarker
            self.hasPart2CAPMarker = hasPart2CAPMarker
            self.cbdComponents = cbdComponents
        }
    }

    /// Parses the main-header `SIZ`, `CAP`, and Part 2 `CBD` markers without allocating or decoding tile data.
    /// Returns `nil` when the input is not a recognizable J2K/JP2 stream or lacks a valid `SIZ`.
    public static func imageHeader(in data: Data) -> ImageHeader? {
        guard let codestream = locateCodestream(in: data),
              readUInt16(codestream, at: 0) == soc else {
            return nil
        }
        var offset = 2
        var parsedWidth: Int?
        var parsedHeight: Int?
        var parsedComponents: [ComponentHeader]?
        var parsedCBDComponents: [ComponentHeader]?
        var hasCAP = false
        var hasPart15CAP = false
        var hasPart2CAP = false

        while let marker = readUInt16(codestream, at: offset) {
            guard marker & 0xFF00 == 0xFF00 else { return nil }
            if marker == sot || marker == sod || marker == eoc { break }
            if marker == soc {
                offset += 2
                continue
            }
            guard let segmentLength = readUInt16(codestream, at: offset + 2),
                  segmentLength >= 2,
                  offset + 2 + Int(segmentLength) <= codestream.count else {
                return nil
            }
            if marker == cap {
                hasCAP = true
                if segmentLength >= 6, let pcap = readUInt32(codestream, at: offset + 4) {
                    if (pcap & 0x0002_0000) != 0 {
                        hasPart15CAP = true
                    }
                    if (pcap & 0x4000_0000) != 0 {
                        hasPart2CAP = true
                    }
                }
            } else if marker == cbd {
                // Lcbd(2) Ncbd(2) Bd^i(1 or count): ISO/IEC 15444-2 Annex I.2.1.
                guard segmentLength >= 5,
                      let ncbd = readUInt16(codestream, at: offset + 4) else {
                    return nil
                }
                let isUniform = (ncbd & 0x8000) != 0
                let count = Int(ncbd & 0x7FFF)
                guard count >= 1 && count <= 16_384 else { return nil }
                if isUniform {
                    guard Int(segmentLength) == 5,
                          let raw = readUInt8(codestream, at: offset + 6) else {
                        return nil
                    }
                    let bitDepth = Int(raw & 0x7F) + 1
                    guard (1...38).contains(bitDepth) else { return nil }
                    let comp = ComponentHeader(
                        bitDepth: bitDepth,
                        isSigned: (raw & 0x80) != 0,
                        subsamplingX: 1,
                        subsamplingY: 1
                    )
                    parsedCBDComponents = Array(repeating: comp, count: count)
                } else {
                    guard Int(segmentLength) == 4 + count else { return nil }
                    var cbdComps: [ComponentHeader] = []
                    cbdComps.reserveCapacity(count)
                    for idx in 0..<count {
                        guard let raw = readUInt8(codestream, at: offset + 6 + idx) else {
                            return nil
                        }
                        let bitDepth = Int(raw & 0x7F) + 1
                        guard (1...38).contains(bitDepth) else { return nil }
                        cbdComps.append(ComponentHeader(
                            bitDepth: bitDepth,
                            isSigned: (raw & 0x80) != 0,
                            subsamplingX: 1,
                            subsamplingY: 1
                        ))
                    }
                    parsedCBDComponents = cbdComps
                }
            } else if marker == siz {
                guard segmentLength >= 38,
                      let xsiz = readUInt32(codestream, at: offset + 6),
                      let ysiz = readUInt32(codestream, at: offset + 10),
                      let xosiz = readUInt32(codestream, at: offset + 14),
                      let yosiz = readUInt32(codestream, at: offset + 18),
                      let csiz = readUInt16(codestream, at: offset + 38),
                      xsiz > xosiz, ysiz > yosiz, csiz >= 1,
                      Int(segmentLength) == 38 + 3 * Int(csiz) else {
                    return nil
                }
                let w = Int(xsiz - xosiz)
                let h = Int(ysiz - yosiz)
                guard w > 0, h > 0 else { return nil }
                var comps: [ComponentHeader] = []
                comps.reserveCapacity(Int(csiz))
                for idx in 0..<Int(csiz) {
                    let base = offset + 40 + idx * 3
                    guard let ssiz = readUInt8(codestream, at: base),
                          let xrsiz = readUInt8(codestream, at: base + 1),
                          let yrsiz = readUInt8(codestream, at: base + 2),
                          xrsiz > 0, yrsiz > 0 else {
                        return nil
                    }
                    let bitDepth = Int(ssiz & 0x7F) + 1
                    let isSigned = (ssiz & 0x80) != 0
                    comps.append(ComponentHeader(
                        bitDepth: bitDepth,
                        isSigned: isSigned,
                        subsamplingX: Int(xrsiz),
                        subsamplingY: Int(yrsiz)
                    ))
                }
                parsedWidth = w
                parsedHeight = h
                parsedComponents = comps
            }
            offset += 2 + Int(segmentLength)
        }

        guard let width = parsedWidth,
              let height = parsedHeight,
              let components = parsedComponents else {
            return nil
        }
        if let cbdComps = parsedCBDComponents, cbdComps.count == components.count {
            parsedCBDComponents = zip(cbdComps, components).map { cbdComp, sizComp in
                ComponentHeader(
                    bitDepth: cbdComp.bitDepth,
                    isSigned: cbdComp.isSigned,
                    subsamplingX: sizComp.subsamplingX,
                    subsamplingY: sizComp.subsamplingY
                )
            }
        }
        return ImageHeader(
            width: width,
            height: height,
            components: components,
            hasCAPMarker: hasCAP,
            hasPart15CAPMarker: hasPart15CAP,
            hasPart2CAPMarker: hasPart2CAP,
            cbdComponents: parsedCBDComponents
        )
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
    private static let qcd: UInt16 = 0xFF5C  // Quantization default
    private static let poc: UInt16 = 0xFF5F  // Progression order change

    /// Repairs J2KSwift 11.0.3's hardcoded `CAP` `Ccap^15 = 0x0020` marker on reversible 5/3
    /// HTJ2K codestreams so the emitted stream conforms to ISO/IEC 15444-15 Annex A Table A.3:
    /// bit 5 (`0x0020`, `HTIRV`) is cleared to `0` (`HTREV`), and bits `0..4` (`MAGB`) are set
    /// from the main-header unquantized `QCD` guard bits and subband exponents.
    /// Non-HTJ2K, irreversible 9/7, or already-conformant codestreams are returned unchanged.
    public static func conformingToReversibleHTJ2KCAP(_ data: Data) -> Data {
        guard readUInt16(data, at: 0) == soc,
              let style = codingStyle(in: data),
              style.reversibleWavelet else {
            return data
        }
        var bytes = [UInt8](data)
        guard let capOffset = mainHeaderSegmentOffset(bytes, marker: cap),
              capOffset + 10 <= bytes.count else {
            return data
        }
        let lcap = Int(bytes[capOffset + 2]) << 8 | Int(bytes[capOffset + 3])
        guard lcap == 8 else { return data }
        let pcap = UInt32(bytes[capOffset + 4]) << 24
            | UInt32(bytes[capOffset + 5]) << 16
            | UInt32(bytes[capOffset + 6]) << 8
            | UInt32(bytes[capOffset + 7])
        let ccap15 = UInt16(bytes[capOffset + 8]) << 8 | UInt16(bytes[capOffset + 9])
        guard pcap == 0x0002_0000, ccap15 == 0x0020 else { return data }

        guard let qcdOffset = mainHeaderSegmentOffset(bytes, marker: qcd),
              qcdOffset + 6 <= bytes.count else {
            return data
        }
        let lqcd = Int(bytes[qcdOffset + 2]) << 8 | Int(bytes[qcdOffset + 3])
        guard lqcd >= 4, qcdOffset + 2 + lqcd <= bytes.count else { return data }
        let sqcd = bytes[qcdOffset + 4]
        guard (sqcd & 0x1F) == 0 else { return data }
        let guardBits = Int(sqcd >> 5)
        var maxExponent = 0
        for idx in (qcdOffset + 5)..<(qcdOffset + 2 + lqcd) {
            maxExponent = max(maxExponent, Int(bytes[idx] >> 3))
        }
        let maxMb = guardBits + maxExponent - 1
        let magb = UInt16(max(0, min(26, maxMb - 8)))
        bytes[capOffset + 8] = UInt8(magb >> 8)
        bytes[capOffset + 9] = UInt8(magb & 0xFF)
        return Data(bytes)
    }

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
    package static func rawCodestreamPayload(in data: Data) -> Data? {
        locateCodestream(in: data)
    }

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

// MARK: - Codestream Conformance, Interoperability, Error Metrics & Benchmarking

/// Structural codestream validator for JPEG 2000 Part 1 / Part 2 / Part 15 (HTJ2K) streams.
public struct HTJ2KConformanceTestHarness: Sendable {
    public init() {}

    /// Validates basic ISO/IEC 15444-1 / 15444-15 codestream structure (`SOC`, `SIZ`, `COD`, `EOC`).
    /// Returns an array of structural violation messages (empty when valid).
    public func validateCodestreamStructure(_ codestream: Data) -> [String] {
        guard codestream.count >= 4 else {
            return ["Codestream too short (\(codestream.count) bytes); missing SOC marker"]
        }
        guard let raw = J2KCodestreamInspector.rawCodestreamPayload(in: codestream),
              raw.count >= 4 else {
            return ["Missing or invalid SOC marker (expected 0xFF4F)"]
        }
        let first0 = raw[raw.startIndex]
        let first1 = raw[raw.index(after: raw.startIndex)]
        guard first0 == 0xFF && first1 == 0x4F else {
            return ["Missing SOC marker at start of codestream (expected 0xFF4F)"]
        }

        var errors: [String] = []
        if J2KCodestreamInspector.imageHeader(in: raw) == nil {
            errors.append("Missing or malformed main-header SIZ marker segment")
        }
        if J2KCodestreamInspector.codingStyle(in: raw) == nil {
            errors.append("Missing or malformed main-header COD marker segment")
        }
        let last0 = raw[raw.index(raw.endIndex, offsetBy: -2)]
        let last1 = raw[raw.index(raw.endIndex, offsetBy: -1)]
        if !(last0 == 0xFF && last1 == 0xD9) {
            errors.append("Missing EOC marker (0xFFD9) at end of codestream")
        }
        return errors
    }
}

/// Interoperability and marker-signalling validator for JPEG 2000 and HTJ2K codestreams.
public struct J2KHTInteroperabilityValidator: Sendable {
    public struct CapabilityResult: Sendable, Equatable {
        public let isHTJ2K: Bool
        public let isMixedMode: Bool
        public let errors: [String]
        public let warnings: [String]

        public init(isHTJ2K: Bool, isMixedMode: Bool, errors: [String], warnings: [String]) {
            self.isHTJ2K = isHTJ2K
            self.isMixedMode = isMixedMode
            self.errors = errors
            self.warnings = warnings
        }
    }

    public struct InteroperabilityResult: Sendable, Equatable {
        public let passed: Bool
        public let isHTJ2K: Bool
        public let isMixedMode: Bool
        public let errors: [String]
        public let warnings: [String]

        public init(passed: Bool, isHTJ2K: Bool, isMixedMode: Bool, errors: [String], warnings: [String]) {
            self.passed = passed
            self.isHTJ2K = isHTJ2K
            self.isMixedMode = isMixedMode
            self.errors = errors
            self.warnings = warnings
        }
    }

    public init() {}

    /// Inspects `CAP` (`0xFF50`) capability signalling for ISO/IEC 15444-15 (HTJ2K).
    public func validateCapabilitySignaling(codestream: Data) -> CapabilityResult {
        guard let raw = J2KCodestreamInspector.rawCodestreamPayload(in: codestream),
              raw.count >= 4 else {
            return CapabilityResult(
                isHTJ2K: false,
                isMixedMode: false,
                errors: ["Cannot inspect capability signalling: missing SOC marker"],
                warnings: []
            )
        }
        let header = J2KCodestreamInspector.imageHeader(in: raw)
        let isHTJ2K = header?.hasPart15CAPMarker ?? false
        var isMixedMode = false
        var errors: [String] = []
        let warnings: [String] = []

        // Inspect CAP Ccap^15 mixed-mode bit (bit 14 = 0x4000, MULTIHT) if present.
        let bytes = [UInt8](raw)
        var offset = 2
        while offset + 4 <= bytes.count, bytes[offset] == 0xFF {
            let marker = (UInt16(bytes[offset]) << 8) | UInt16(bytes[offset + 1])
            if marker == 0xFF90 || marker == 0xFF93 || marker == 0xFFD9 { break }
            let segLen = (Int(bytes[offset + 2]) << 8) | Int(bytes[offset + 3])
            guard segLen >= 2, offset + 2 + segLen <= bytes.count else {
                errors.append("Truncated main-header marker segment 0x\(String(format: "%04X", marker))")
                break
            }
            if marker == 0xFF50 {
                if segLen < 8 {
                    errors.append("CAP marker segment length (\(segLen)) is shorter than minimum 8 bytes")
                } else {
                    let pcap = (UInt32(bytes[offset + 4]) << 24)
                        | (UInt32(bytes[offset + 5]) << 16)
                        | (UInt32(bytes[offset + 6]) << 8)
                        | UInt32(bytes[offset + 7])
                    if (pcap & 0x0002_0000) != 0 {
                        // Count set bits higher than bit 17 to find Ccap^15 index.
                        let higherMask = pcap & ~UInt32(0x0003_FFFF)
                        let ccapIndex = higherMask.nonzeroBitCount
                        let ccapOffset = offset + 8 + ccapIndex * 2
                        if ccapOffset + 2 <= offset + 2 + segLen {
                            let ccap15 = (UInt16(bytes[ccapOffset]) << 8) | UInt16(bytes[ccapOffset + 1])
                            if (ccap15 & 0x4000) != 0 {
                                isMixedMode = true
                            }
                        } else {
                            errors.append("CAP marker declares Pcap^15 without corresponding Ccap^15 field")
                        }
                    }
                }
            }
            offset += 2 + segLen
        }

        return CapabilityResult(
            isHTJ2K: isHTJ2K,
            isMixedMode: isMixedMode,
            errors: errors,
            warnings: warnings
        )
    }

    /// Validates ISO/IEC 15444-1 Annex A main-header marker ordering (`SOC`, immediately `SIZ`, then `COD`/`QCD` before `SOT`).
    public func validateMarkerOrdering(codestream: Data) -> [String] {
        guard let raw = J2KCodestreamInspector.rawCodestreamPayload(in: codestream),
              raw.count >= 4 else {
            return ["Codestream does not start with SOC (0xFF4F)"]
        }
        let bytes = [UInt8](raw)
        guard bytes[0] == 0xFF, bytes[1] == 0x4F else {
            return ["Codestream does not start with SOC (0xFF4F)"]
        }
        guard bytes[2] == 0xFF, bytes[3] == 0x51 else {
            return ["SIZ (0xFF51) must immediately follow SOC (0xFF4F) at offset 2"]
        }

        var issues: [String] = []
        var seenCOD = false
        var seenQCD = false
        var seenSOT = false
        var offset = 2
        while offset + 4 <= bytes.count, bytes[offset] == 0xFF {
            let marker = (UInt16(bytes[offset]) << 8) | UInt16(bytes[offset + 1])
            if marker == 0xFF90 {
                seenSOT = true
                break
            }
            if marker == 0xFF93 || marker == 0xFFD9 { break }
            let segLen = (Int(bytes[offset + 2]) << 8) | Int(bytes[offset + 3])
            guard segLen >= 2, offset + 2 + segLen <= bytes.count else { break }
            if marker == 0xFF52 { seenCOD = true }
            if marker == 0xFF5C { seenQCD = true }
            offset += 2 + segLen
        }
        if !seenCOD {
            issues.append("Missing required COD (0xFF52) marker segment in main header")
        }
        if !seenQCD {
            issues.append("Missing required QCD (0xFF5C) marker segment in main header")
        }
        if !seenSOT {
            issues.append("Missing SOT (0xFF90) tile-part header in codestream")
        }
        return issues
    }

    /// Validates marker segment length fields (`Lmar`) across the main header and tile-part headers.
    public func validateSegmentLengths(codestream: Data) -> [String] {
        guard codestream.count >= 4 else {
            return ["Codestream truncated (\(codestream.count) bytes)"]
        }
        guard let raw = J2KCodestreamInspector.rawCodestreamPayload(in: codestream) else {
            return ["Codestream lacks valid SOC marker or JP2 codestream box"]
        }
        let bytes = [UInt8](raw)
        guard bytes.count >= 4, bytes[0] == 0xFF, bytes[1] == 0x4F else {
            return ["Codestream lacks valid SOC marker (0xFF4F)"]
        }

        var errors: [String] = []
        var offset = 2
        var reachedTileDataOrEOC = false

        while offset < bytes.count {
            guard offset + 2 <= bytes.count else {
                errors.append("Truncated 2-byte marker at offset \(offset)")
                break
            }
            guard bytes[offset] == 0xFF else {
                errors.append("Expected marker prefix 0xFF at offset \(offset), found 0x\(String(format: "%02X", bytes[offset]))")
                break
            }
            let marker = (UInt16(bytes[offset]) << 8) | UInt16(bytes[offset + 1])
            if marker == 0xFFD9 {
                reachedTileDataOrEOC = true
                break
            }
            if marker == 0xFF4F {
                offset += 2
                continue
            }
            guard offset + 4 <= bytes.count else {
                errors.append("Truncated segment length for marker 0x\(String(format: "%04X", marker)) at offset \(offset)")
                break
            }
            let segLen = (Int(bytes[offset + 2]) << 8) | Int(bytes[offset + 3])
            guard segLen >= 2 else {
                errors.append("Invalid segment length \(segLen) (< 2) for marker 0x\(String(format: "%04X", marker))")
                break
            }
            guard offset + 2 + segLen <= bytes.count else {
                errors.append(
                    "Segment length \(segLen) for marker 0x\(String(format: "%04X", marker)) at offset \(offset) overruns codestream (\(bytes.count) bytes)"
                )
                break
            }
            if marker == 0xFF90 {
                guard segLen == 10 else {
                    errors.append("SOT marker length must be 10, got \(segLen)")
                    break
                }
                let psot = (UInt64(bytes[offset + 6]) << 24)
                    | (UInt64(bytes[offset + 7]) << 16)
                    | (UInt64(bytes[offset + 8]) << 8)
                    | UInt64(bytes[offset + 9])
                // Validate tile-part header segments up to SOD (0xFF93).
                var tpOffset = offset + 12
                var foundSOD = false
                while tpOffset + 2 <= bytes.count {
                    guard bytes[tpOffset] == 0xFF else {
                        errors.append("Malformed marker inside tile-part header at offset \(tpOffset)")
                        break
                    }
                    let tpMarker = (UInt16(bytes[tpOffset]) << 8) | UInt16(bytes[tpOffset + 1])
                    if tpMarker == 0xFF93 {
                        foundSOD = true
                        break
                    }
                    guard tpOffset + 4 <= bytes.count else {
                        errors.append("Truncated tile-part marker 0x\(String(format: "%04X", tpMarker))")
                        break
                    }
                    let tpLen = (Int(bytes[tpOffset + 2]) << 8) | Int(bytes[tpOffset + 3])
                    guard tpLen >= 2, tpOffset + 2 + tpLen <= bytes.count else {
                        errors.append("Tile-part marker 0x\(String(format: "%04X", tpMarker)) length \(tpLen) overruns codestream")
                        break
                    }
                    tpOffset += 2 + tpLen
                }
                if !foundSOD && errors.isEmpty {
                    errors.append("Tile-part starting at offset \(offset) missing SOD (0xFF93) marker")
                    break
                }
                reachedTileDataOrEOC = true
                if psot == 0 {
                    break
                }
                guard psot >= 14, offset + Int(psot) <= bytes.count else {
                    errors.append("SOT Psot (\(psot)) at offset \(offset) overruns codestream (\(bytes.count) bytes)")
                    break
                }
                offset += Int(psot)
                continue
            }
            offset += 2 + segLen
        }

        if errors.isEmpty && !reachedTileDataOrEOC {
            errors.append("Codestream ended before tile-part header or EOC")
        }
        return errors
    }

    /// Runs full structural, marker-ordering, segment-length, and capability validation.
    public func validateInteroperability(codestream: Data) -> InteroperabilityResult {
        let structureErrors = HTJ2KConformanceTestHarness().validateCodestreamStructure(codestream)
        let orderingErrors = validateMarkerOrdering(codestream: codestream)
        let segmentErrors = validateSegmentLengths(codestream: codestream)
        let cap = validateCapabilitySignaling(codestream: codestream)
        let allErrors = structureErrors + orderingErrors + segmentErrors + cap.errors
        return InteroperabilityResult(
            passed: allErrors.isEmpty,
            isHTJ2K: cap.isHTJ2K,
            isMixedMode: cap.isMixedMode,
            errors: allErrors,
            warnings: cap.warnings
        )
    }
}

/// Pixel-level error metrics (MSE, PSNR, MAE) for JPEG 2000 / HTJ2K fidelity verification.
public struct J2KErrorMetrics: Sendable {
    public init() {}

    /// Mean Squared Error between two sample arrays, or `nil` if empty or length-mismatched.
    public static func meanSquaredError(reference: [Int32], test: [Int32]) -> Double? {
        guard !reference.isEmpty, reference.count == test.count else { return nil }
        var sumSq: Double = 0
        for i in 0..<reference.count {
            let diff = Double(reference[i]) - Double(test[i])
            sumSq += diff * diff
        }
        return sumSq / Double(reference.count)
    }

    /// Peak Signal-to-Noise Ratio (dB) between two sample arrays (`+infinity` when identical).
    public static func peakSignalToNoiseRatio(
        reference: [Int32],
        test: [Int32],
        bitDepth: Int = 8
    ) -> Double? {
        guard bitDepth >= 1, bitDepth <= 31,
              let mse = meanSquaredError(reference: reference, test: test) else {
            return nil
        }
        if mse == 0.0 { return .infinity }
        let peak = Double((1 << bitDepth) - 1)
        return 20.0 * log10(peak) - 10.0 * log10(mse)
    }

    /// Maximum Absolute Error between two sample arrays, or `nil` if empty or length-mismatched.
    public static func maximumAbsoluteError(reference: [Int32], test: [Int32]) -> Int? {
        guard !reference.isEmpty, reference.count == test.count else { return nil }
        var maxErr: Int = 0
        for i in 0..<reference.count {
            let err = Int((Int64(reference[i]) - Int64(test[i])).magnitude)
            if err > maxErr { maxErr = err }
        }
        return maxErr
    }

    /// Returns `true` when every sample pair differs by at most `maxError`.
    public static func withinTolerance(reference: [Int32], test: [Int32], maxError: Int) -> Bool {
        guard maxError >= 0, let mae = maximumAbsoluteError(reference: reference, test: test) else {
            return false
        }
        return mae <= maxError
    }

    /// Mean Squared Error across all components of two `J2KImage` values.
    public static func meanSquaredError(reference: J2KImage, test: J2KImage) -> Double? {
        guard let (refSamples, tstSamples) = extractSamples(reference: reference, test: test) else {
            return nil
        }
        return meanSquaredError(reference: refSamples, test: tstSamples)
    }

    /// Peak Signal-to-Noise Ratio across all components of two `J2KImage` values.
    public static func peakSignalToNoiseRatio(
        reference: J2KImage,
        test: J2KImage,
        bitDepth: Int? = nil
    ) -> Double? {
        guard let (refSamples, tstSamples) = extractSamples(reference: reference, test: test) else {
            return nil
        }
        let depth = bitDepth ?? reference.components.first?.bitDepth ?? 8
        return peakSignalToNoiseRatio(reference: refSamples, test: tstSamples, bitDepth: depth)
    }

    /// Maximum Absolute Error across all components of two `J2KImage` values.
    public static func maximumAbsoluteError(reference: J2KImage, test: J2KImage) -> Int? {
        guard let (refSamples, tstSamples) = extractSamples(reference: reference, test: test) else {
            return nil
        }
        return maximumAbsoluteError(reference: refSamples, test: tstSamples)
    }

    private static func extractSamples(reference: J2KImage, test: J2KImage) -> ([Int32], [Int32])? {
        guard reference.width == test.width,
              reference.height == test.height,
              !reference.components.isEmpty,
              reference.components.count == test.components.count else {
            return nil
        }
        var refOut: [Int32] = []
        var tstOut: [Int32] = []
        for (rc, tc) in zip(reference.components, test.components) {
            guard rc.width == tc.width, rc.height == tc.height, rc.bitDepth == tc.bitDepth else {
                return nil
            }
            guard let rs = componentSamples(rc), let ts = componentSamples(tc), rs.count == ts.count else {
                return nil
            }
            refOut.append(contentsOf: rs)
            tstOut.append(contentsOf: ts)
        }
        return (refOut, tstOut)
    }

    private static func componentSamples(_ comp: J2KComponent) -> [Int32]? {
        let count = comp.width * comp.height
        let bps = comp.bytesPerSample
        guard comp.data.count >= count * bps else { return nil }
        var out: [Int32] = []
        out.reserveCapacity(count)
        let base = comp.data.startIndex
        if bps == 1 {
            for i in 0..<count {
                let b = comp.data[comp.data.index(base, offsetBy: i)]
                out.append(comp.signed ? Int32(Int8(bitPattern: b)) : Int32(b))
            }
        } else {
            for i in 0..<count {
                let lo = UInt16(comp.data[comp.data.index(base, offsetBy: i * 2)])
                let hi = UInt16(comp.data[comp.data.index(base, offsetBy: i * 2 + 1)]) << 8
                let word = lo | hi
                out.append(comp.signed ? Int32(Int16(bitPattern: word)) : Int32(word))
            }
        }
        return out
    }
}

/// Lightweight wall-clock benchmark timer for JPEG 2000 / HTJ2K operations.
public struct J2KBenchmark: Sendable {
    public struct Result: Sendable, Equatable {
        public let name: String
        public let iterations: Int
        /// Average duration per iteration in seconds.
        public let averageTime: Double
        /// Minimum duration in seconds.
        public let minTime: Double
        /// Maximum duration in seconds.
        public let maxTime: Double
        /// Median duration in seconds.
        public let medianTime: Double
        /// Sample standard deviation in seconds.
        public let standardDeviation: Double
        /// Mean throughput in operations per second.
        public let operationsPerSecond: Double
    }

    public let name: String

    public init(name: String) {
        self.name = name
    }

    public func measureThrowing(
        iterations: Int,
        warmupIterations: Int = 0,
        _ block: () throws -> Void
    ) rethrows -> Result {
        let warmups = max(0, warmupIterations)
        let runs = max(1, iterations)
        for _ in 0..<warmups {
            try block()
        }
        var samples: [Double] = []
        samples.reserveCapacity(runs)
        let clock = ContinuousClock()
        for _ in 0..<runs {
            let start = clock.now
            try block()
            let elapsed = start.duration(to: clock.now)
            samples.append(Self.seconds(from: elapsed))
        }
        return Self.summarize(name: name, samples: samples)
    }

    public func measureAsyncThrowing(
        iterations: Int,
        warmupIterations: Int = 0,
        _ block: () async throws -> Void
    ) async rethrows -> Result {
        let warmups = max(0, warmupIterations)
        let runs = max(1, iterations)
        for _ in 0..<warmups {
            try await block()
        }
        var samples: [Double] = []
        samples.reserveCapacity(runs)
        let clock = ContinuousClock()
        for _ in 0..<runs {
            let start = clock.now
            try await block()
            let elapsed = start.duration(to: clock.now)
            samples.append(Self.seconds(from: elapsed))
        }
        return Self.summarize(name: name, samples: samples)
    }

    private static func seconds(from duration: Duration) -> Double {
        let (sec, atto) = duration.components
        return Double(sec) + Double(atto) * 1e-18
    }

    private static func summarize(name: String, samples: [Double]) -> Result {
        let sorted = samples.sorted()
        let n = sorted.count
        let sum = sorted.reduce(0.0, +)
        let avg = sum / Double(max(1, n))
        let minVal = sorted.first ?? 0.0
        let maxVal = sorted.last ?? 0.0
        let median: Double
        if n == 0 {
            median = 0.0
        } else if n % 2 == 1 {
            median = sorted[n / 2]
        } else {
            median = 0.5 * (sorted[n / 2 - 1] + sorted[n / 2])
        }
        let variance: Double
        if n > 1 {
            let sq = sorted.reduce(0.0) { $0 + ($1 - avg) * ($1 - avg) }
            variance = sq / Double(n)
        } else {
            variance = 0.0
        }
        let stdDev = variance.squareRoot()
        let ops = avg > 0 ? (1.0 / avg) : 0.0
        return Result(
            name: name,
            iterations: n,
            averageTime: avg,
            minTime: minVal,
            maxTime: maxVal,
            medianTime: median,
            standardDeviation: stdDev,
            operationsPerSecond: ops
        )
    }
}
