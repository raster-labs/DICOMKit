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
}
