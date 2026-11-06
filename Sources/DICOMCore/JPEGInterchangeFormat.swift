// NEMA-verified: 2026a, checked 2026-10-01 — PS3.5 2026a 8.2.1: "The JFIF APP0 marker segment is NOT required to be present in DICOM encapsulated JPEG bit streams, and should not be relied upon to recognize the color space. Its presence is not forbidden …, but it is recommended that it be absent" (D190). The marker syntax is ITU-T T.81 B.1 and JFIF (ITU-T T.871), outside DICOM.

import Foundation

/// Marker-level edits of a JPEG Interchange Format stream (ITU-T T.81 B.1) written for
/// encapsulation in DICOM.
public enum JPEGInterchangeFormat {

    /// Returns `stream` without its JFIF APP0 marker segments (identifier "JFIF\0" or the
    /// JFIF extension "JFXX\0"), which PS3.5 2026a 8.2.1 recommends be absent from DICOM
    /// encapsulated JPEG. Only the table/miscellaneous segments before the first frame header
    /// are examined; the entropy-coded data is never touched. A stream that does not start
    /// with SOI, or whose header cannot be walked, is returned unchanged.
    public static func removingJFIFSegments(_ stream: Data) -> Data {
        let bytes = [UInt8](stream)
        guard bytes.count >= 4, bytes[0] == 0xFF, bytes[1] == 0xD8 else { return stream }
        var out: [UInt8] = [0xFF, 0xD8]
        out.reserveCapacity(bytes.count)
        var offset = 2
        var removed = false
        while offset + 4 <= bytes.count, bytes[offset] == 0xFF {
            let marker = bytes[offset + 1]
            // SOFn (C0-CF except DHT C4, JPG C8, DAC CC) or SOS ends the scan of the header.
            let isFrameOrScan = (0xC0...0xCF).contains(marker) && ![0xC4, 0xC8, 0xCC].contains(marker)
            if isFrameOrScan || marker == 0xDA { break }
            let length = Int(bytes[offset + 2]) << 8 | Int(bytes[offset + 3])
            guard length >= 2, offset + 2 + length <= bytes.count else { return stream }
            let segment = bytes[offset..<(offset + 2 + length)]
            let identifier = Array(bytes[(offset + 4)..<min(offset + 9, offset + 2 + length)])
            if marker == 0xE0, identifier == Array("JFIF\0".utf8) || identifier == Array("JFXX\0".utf8) {
                removed = true
            } else {
                out.append(contentsOf: segment)
            }
            offset += 2 + length
        }
        guard removed else { return stream }
        out.append(contentsOf: bytes[offset...])
        return Data(out)
    }

    /// Promotes the encoder's 8-bit monochrome baseline sequential stream to the
    /// equivalent extended sequential process. Only the SOF marker changes; tables,
    /// scan headers and entropy bytes remain identical. PS3.5 A.4.1 requires SOF1
    /// for .51 even when the coding needs no features beyond baseline's subset.
    /// This is an encoder adaptation, never a decoder mismatch recovery policy.
    static func promotingEightBitBaselineToExtended(_ stream: Data) throws -> Data {
        let header = try JPEGFrameEnvelope.parse(stream, jpegLS: false)
        guard header.precision == 8, header.components.count == 1,
              header.process == 0xC0 || header.process == 0xC1 else {
            throw DICOMError.parsingFailed("Extended 8-bit encoding requires a monochrome sequential JPEG stream")
        }
        if header.process == 0xC1 { return stream }
        var bytes = [UInt8](stream)
        var offset = 2 // SOI was validated by the bounded envelope parser.
        while offset < bytes.count {
            guard bytes[offset] == 0xFF else { break }
            while offset < bytes.count, bytes[offset] == 0xFF { offset += 1 }
            guard offset < bytes.count else { break }
            let markerOffset = offset
            let marker = bytes[offset]
            offset += 1
            guard marker != 0xDA, offset + 2 <= bytes.count else { break }
            let length = Int(bytes[offset]) << 8 | Int(bytes[offset + 1])
            guard length >= 2, length <= bytes.count - offset else { break }
            if marker == 0xC0 {
                bytes[markerOffset] = 0xC1
                return Data(bytes)
            }
            offset += length
        }
        throw DICOMError.parsingFailed("Extended encoder output has no bounded SOF0 marker before SOS")
    }

    /// One frame component of a frame header (ITU-T T.81 B.2.2): identifier and its
    /// horizontal / vertical sampling factors.
    public struct FrameComponent: Sendable, Equatable {
        public let identifier: UInt8
        public let horizontalSampling: Int
        public let verticalSampling: Int
    }

    /// The components of the first frame header (SOF0 … SOF15, not DHT / JPG / DAC), or `nil`
    /// when the stream has no readable frame header before its first scan.
    public static func frameComponents(in stream: Data) -> [FrameComponent]? {
        let bytes = [UInt8](stream)
        guard bytes.count >= 4, bytes[0] == 0xFF, bytes[1] == 0xD8 else { return nil }
        var offset = 2
        while offset + 4 <= bytes.count, bytes[offset] == 0xFF {
            let marker = bytes[offset + 1]
            if marker == 0xFF { offset += 1; continue }           // fill byte
            if marker == 0xDA { return nil }                      // SOS before any SOF
            let length = Int(bytes[offset + 2]) << 8 | Int(bytes[offset + 3])
            guard length >= 2, offset + 2 + length <= bytes.count else { return nil }
            let isFrame = (0xC0...0xCF).contains(marker) && ![0xC4, 0xC8, 0xCC].contains(marker)
            if isFrame {
                // Lf(2) P(1) Y(2) X(2) Nf(1), then Nf × (Ci, Hi<<4|Vi, Tqi).
                guard length >= 8 else { return nil }
                let count = Int(bytes[offset + 9])
                guard length >= 8 + 3 * count else { return nil }
                return (0..<count).map { k in
                    let o = offset + 10 + 3 * k
                    return FrameComponent(identifier: bytes[o],
                                          horizontalSampling: Int(bytes[o + 1] >> 4),
                                          verticalSampling: Int(bytes[o + 1] & 0x0F))
                }
            }
            offset += 2 + length
        }
        return nil
    }

    /// Whether the frame has three components with the first sampled at twice the horizontal
    /// rate of the other two and all at the same vertical rate (H 2,1,1; V 1,1,1): the 4:2:2
    /// layout of YBR_FULL_422 ("CB and CR values are sampled horizontally at half the Y rate",
    /// PS3.3 2026a C.7.6.3.1.2).
    public static func isHorizontally422(_ stream: Data) -> Bool {
        guard let c = frameComponents(in: stream), c.count == 3 else { return false }
        return c[0].horizontalSampling == 2 && c[1].horizontalSampling == 1 && c[2].horizontalSampling == 1
            && c[0].verticalSampling == 1 && c[1].verticalSampling == 1 && c[2].verticalSampling == 1
    }

    /// Whether the stream carries a JFIF APP0 marker segment before its frame header.
    public static func containsJFIFSegment(_ stream: Data) -> Bool {
        removingJFIFSegments(stream).count != stream.count
    }

    /// Rewrites 3-component Lossless JPEG (`SOF3`, `0xC3`) frame and scan component
    /// identifiers to ASCII `'R'`, `'G'`, `'B'` (`0x52`, `0x47`, `0x42`) when an external
    /// encoder emitted numeric component IDs (such as `1, 2, 3`).
    ///
    /// `SwiftJLI` requires explicit `'R','G','B'` component identifiers on 3-component
    /// `SOF3` streams because `SOF3` applies no colour transform. Segment lengths and
    /// entropy-coded bytes are never altered; malformed headers return `stream` unchanged
    /// so the downstream envelope/codec parser rejects them normally.
    static func normalizingLosslessRGBComponentIDs(_ stream: Data) -> Data {
        guard stream.count >= 20 else { return stream }
        var bytes = [UInt8](stream)
        guard bytes[0] == 0xFF, bytes[1] == 0xD8 else { return stream }
        var offset = 2
        var idMap: (c0: UInt8, c1: UInt8, c2: UInt8)?

        while offset < bytes.count {
            guard bytes[offset] == 0xFF else { return stream }
            while offset < bytes.count, bytes[offset] == 0xFF { offset += 1 }
            guard offset < bytes.count else { return stream }
            let marker = bytes[offset]
            offset += 1
            if marker == 0xD9 || marker == 0x00 || (0xD0...0xD8).contains(marker) {
                return stream
            }
            guard offset + 2 <= bytes.count else { return stream }
            let length = (Int(bytes[offset]) << 8) | Int(bytes[offset + 1])
            guard length >= 2, length <= bytes.count - offset else { return stream }
            let payload = offset + 2

            if marker == 0xC3 {
                guard idMap == nil, length == 17, bytes[payload + 5] == 3 else { return stream }
                let c0 = bytes[payload + 6]
                let c1 = bytes[payload + 9]
                let c2 = bytes[payload + 12]
                if c0 == 0x52 && c1 == 0x47 && c2 == 0x42 {
                    return stream
                }
                guard c0 != c1, c1 != c2, c0 != c2 else { return stream }
                idMap = (c0, c1, c2)
                bytes[payload + 6] = 0x52
                bytes[payload + 9] = 0x47
                bytes[payload + 12] = 0x42
            } else if marker == 0xDA {
                guard let map = idMap, length == 12, bytes[payload] == 3 else { return stream }
                for j in 0..<3 {
                    let csIndex = payload + 1 + 2 * j
                    switch bytes[csIndex] {
                    case map.c0: bytes[csIndex] = 0x52
                    case map.c1: bytes[csIndex] = 0x47
                    case map.c2: bytes[csIndex] = 0x42
                    default: return stream
                    }
                }
                return Data(bytes)
            } else if (0xC0...0xCF).contains(marker), ![0xC4, 0xC8, 0xCC].contains(marker) {
                return stream
            }

            offset += length
        }
        return stream
    }

    /// Strips ancillary `APPn` (`0xE0...0xEF`) and `COM` (`0xFE`) marker segments from a
    /// validated JPEG Interchange Format stream after DICOM envelope admission has already
    /// recorded any JFIF / Adobe APP14 colour signalling.
    ///
    /// Returns `stream` unchanged without copying when no ancillary `APPn`/`COM` segments
    /// exist (the common case for `SwiftJLI`-encoded DICOM frames). When rewriting, stops
    /// cleanly at `EOI` (`0xFF 0xD9`) so odd-length segment removal never leaves an invalid
    /// trailing padding byte at an even offset.
    static func removingAncillaryMetadataSegments(_ stream: Data) -> Data {
        let needsRewrite: Bool = stream.withUnsafeBytes { raw in
            guard raw.count >= 4, raw[0] == 0xFF, raw[1] == 0xD8 else { return false }
            var p = 2
            var entropy = false
            while p < raw.count {
                if entropy {
                    while p < raw.count {
                        if raw[p] != 0xFF { p += 1; continue }
                        guard p + 1 < raw.count else { return false }
                        let next = raw[p + 1]
                        if next == 0x00 || (0xD0...0xD7).contains(next) { p += 2; continue }
                        break
                    }
                    entropy = false
                }
                guard p + 1 < raw.count, raw[p] == 0xFF else { return false }
                while p < raw.count, raw[p] == 0xFF { p += 1 }
                guard p < raw.count else { return false }
                let marker = raw[p]
                p += 1
                if marker == 0xD9 { return false }
                if (0xE0...0xEF).contains(marker) || marker == 0xFE { return true }
                guard marker != 0xD8, marker != 0x00, !(0xD0...0xD7).contains(marker),
                      p + 2 <= raw.count else { return false }
                let length = (Int(raw[p]) << 8) | Int(raw[p + 1])
                guard length >= 2, length <= raw.count - p else { return false }
                if marker == 0xDA { entropy = true }
                p += length
            }
            return false
        }
        guard needsRewrite else { return stream }

        return stream.withUnsafeBytes { raw -> Data in
            guard let base = raw.baseAddress?.assumingMemoryBound(to: UInt8.self),
                  raw.count >= 4, base[0] == 0xFF, base[1] == 0xD8 else {
                return stream
            }
            var out = Data()
            out.reserveCapacity(raw.count)
            out.append(base, count: 2)
            var p = 2
            var entropy = false
            while p < raw.count {
                if entropy {
                    let entropyStart = p
                    while p < raw.count {
                        if base[p] != 0xFF { p += 1; continue }
                        guard p + 1 < raw.count else { return stream }
                        let next = base[p + 1]
                        if next == 0x00 || (0xD0...0xD7).contains(next) { p += 2; continue }
                        break
                    }
                    if p > entropyStart {
                        out.append(base.advanced(by: entropyStart), count: p - entropyStart)
                    }
                    entropy = false
                }
                guard p + 1 < raw.count, base[p] == 0xFF else { return stream }
                while p < raw.count, base[p] == 0xFF { p += 1 }
                guard p < raw.count else { return stream }
                let marker = base[p]
                p += 1
                if marker == 0xD9 {
                    out.append(contentsOf: [0xFF, 0xD9])
                    return out
                }
                guard marker != 0xD8, marker != 0x00, !(0xD0...0xD7).contains(marker),
                      p + 2 <= raw.count else { return stream }
                let length = (Int(base[p]) << 8) | Int(base[p + 1])
                guard length >= 2, length <= raw.count - p else { return stream }
                let segmentEnd = p + length
                if !((0xE0...0xEF).contains(marker) || marker == 0xFE) {
                    out.append(contentsOf: [0xFF, marker])
                    out.append(base.advanced(by: p), count: length)
                }
                if marker == 0xDA { entropy = true }
                p = segmentEnd
            }
            return stream
        }
    }
}
