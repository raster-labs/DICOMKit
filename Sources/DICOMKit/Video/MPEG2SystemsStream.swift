// NEMA-verified: 2026a, checked 2026-10-06 — MPEG2SystemsLayer maps onto VideoContainer.mpegPS / .mpegPES and takes its display name from there (PS3.5 2026a 8.2.5 / 8.2.6 container list) (D237)
// NEMA-verified: 2026a, checked 2026-10-01 — PS3.5 2026a 8.2.5 / 8.2.6: "The container format for the video bit stream is not constrained. For example, it may MPEG-2 Transport Stream (MPEG-TS), MPEG-2 Program Stream (MPEG-PS), MPEG-2 Elementary Stream (MPEG-ES), MPEG-2 Packetized Elementary Stream (MPEG-PES) … or MPEG-4 (MP4) container"; PS / PES are recognised and their video PES payloads read for probing (D227); the packet syntax itself is ISO/IEC 13818-1 (out of scope)
//
// MPEG2SystemsStream.swift
// DICOMKit
//
// Copyright © 2026 DICOMKit. All rights reserved.
//

import Foundation

/// An MPEG-2 systems-layer wrapping (ISO/IEC 13818-1) other than the Transport
/// Stream, which PS3.5 2026a 8.2.5 / 8.2.6 list among the permitted containers of
/// an MPEG-2 video bit stream.
///
/// ``VideoContainer`` reports them as ``VideoContainer/mpegPS`` and
/// ``VideoContainer/mpegPES`` (D237); this type is what the byte-level reader
/// identifies and what ``VideoProbeResult/mpeg2SystemsLayer`` carries.
public enum MPEG2SystemsLayer: String, Sendable, Hashable, CaseIterable {
    /// MPEG-2 Program Stream (MPEG-PS): pack headers (00 00 01 BA) and PES packets.
    case programStream
    /// MPEG-2 Packetized Elementary Stream (MPEG-PES): PES packets without packs.
    case packetizedElementaryStream

    /// The PS3.5 8.2.5 name; identical to ``VideoContainer/displayName`` of ``container``.
    public var displayName: String { container.displayName }

    /// The ``VideoContainer`` case that reports this systems layer (D237).
    public var container: VideoContainer {
        switch self {
        case .programStream: return .mpegPS
        case .packetizedElementaryStream: return .mpegPES
        }
    }
}

extension MP4ContainerParser {

    /// The MPEG-2 systems layer the bytes begin with, or nil for anything else
    /// (including a Transport Stream and a bare elementary stream).
    ///
    /// A Program Stream begins with a pack header, start code 00 00 01 BA, whose
    /// next byte carries the '01' (MPEG-2) or '0010' (MPEG-1) marker; a PES stream
    /// begins with a video PES packet, 00 00 01 E0-EF (ISO/IEC 13818-1 2.4.3.6,
    /// 2.5.3.3).
    public static func mpeg2SystemsLayer(_ data: Data) -> MPEG2SystemsLayer? {
        let bytes = [UInt8](data.prefix(16))
        guard bytes.count >= 6, bytes[0] == 0, bytes[1] == 0, bytes[2] == 1 else { return nil }
        switch bytes[3] {
        case 0xBA:
            if bytes[4] & 0xC0 == 0x40 || bytes[4] & 0xF0 == 0x20 { return .programStream }
            return nil
        case 0xE0...0xEF:
            return .packetizedElementaryStream
        default:
            return nil
        }
    }

    /// One PES packet's place in a systems stream.
    struct MPEG2SystemsPacket {
        let streamID: UInt8
        /// The packet's PES payload (after the PES header), for packets that have one.
        let payload: Range<Int>?
    }

    /// Walks the packs and PES packets of a Program Stream or PES stream.
    ///
    /// Stops at the MPEG_program_end_code (00 00 01 B9), at the end of the data,
    /// or at bytes that are not a systems-layer start code.
    static func mpeg2SystemsPackets(_ data: Data) -> [MPEG2SystemsPacket] {
        let bytes = [UInt8](data)
        let count = bytes.count
        var packets: [MPEG2SystemsPacket] = []
        var offset = 0

        func isStartCode(at i: Int) -> Bool {
            i + 3 < count && bytes[i] == 0 && bytes[i + 1] == 0 && bytes[i + 2] == 1
        }
        /// The next systems-layer start code (stream_id 0xB9 or above) at or after `i`.
        func nextSystemsStartCode(from i: Int) -> Int {
            var j = i
            while j + 3 < count {
                if bytes[j] == 0, bytes[j + 1] == 0, bytes[j + 2] == 1, bytes[j + 3] >= 0xB9 { return j }
                j += 1
            }
            return count
        }

        while isStartCode(at: offset) {
            let code = bytes[offset + 3]
            switch code {
            case 0xB9:
                return packets
            case 0xBA:
                guard offset + 4 < count else { return packets }
                if bytes[offset + 4] & 0xC0 == 0x40 {
                    guard offset + 13 < count else { return packets }
                    offset += 14 + Int(bytes[offset + 13] & 0x07)
                } else if bytes[offset + 4] & 0xF0 == 0x20 {
                    offset += 12
                } else {
                    return packets
                }
            case 0xBB...0xFF:
                guard offset + 5 < count else { return packets }
                let length = Int(bytes[offset + 4]) << 8 | Int(bytes[offset + 5])
                let start = offset + 6
                let end = length == 0 ? nextSystemsStartCode(from: start) : min(count, start + length)
                packets.append(MPEG2SystemsPacket(
                    streamID: code, payload: pesPayload(bytes, streamID: code, range: start..<end)))
                offset = end
            default:
                return packets
            }
        }
        return packets
    }

    /// The payload range of a PES packet whose header starts at `range.lowerBound`.
    private static func pesPayload(_ bytes: [UInt8], streamID: UInt8, range: Range<Int>) -> Range<Int>? {
        // program_stream_map, padding, private_stream_2, ECM, EMM, DSMCC, H.222.1 type E and
        // the directory carry no PES header extension (ISO/IEC 13818-1 Table 2-21).
        switch streamID {
        case 0xBC, 0xBE, 0xBF, 0xF0, 0xF1, 0xF2, 0xF8, 0xFF:
            return range
        case 0xBB:
            return nil  // system header
        default:
            break
        }
        var i = range.lowerBound
        guard i < range.upperBound else { return nil }
        if bytes[i] & 0xC0 == 0x80 {
            // MPEG-2 PES header: two flag bytes, then PES_header_data_length.
            guard i + 2 < range.upperBound else { return nil }
            let start = i + 3 + Int(bytes[i + 2])
            return start <= range.upperBound ? start..<range.upperBound : nil
        }
        // MPEG-1 packet header (ISO/IEC 11172-1 2.4.3.3): stuffing, STD buffer, PTS / DTS.
        while i < range.upperBound, bytes[i] == 0xFF { i += 1 }
        guard i < range.upperBound else { return nil }
        if bytes[i] & 0xC0 == 0x40 { i += 2 }
        guard i < range.upperBound else { return nil }
        switch bytes[i] & 0xF0 {
        case 0x20: i += 5
        case 0x30: i += 10
        default:
            guard bytes[i] == 0x0F else { return nil }
            i += 1
        }
        return i <= range.upperBound ? i..<range.upperBound : nil
    }

    /// The video elementary stream of a Program Stream or PES stream: the payloads of
    /// the PES packets of the first video stream_id (0xE0-0xEF) concatenated, or nil
    /// when the bytes are not such a stream or carry no video.
    public static func mpeg2VideoElementaryStream(_ data: Data) -> Data? {
        guard mpeg2SystemsLayer(data) != nil else { return nil }
        let packets = mpeg2SystemsPackets(data)
        guard let videoID = packets.first(where: { (0xE0...0xEF).contains($0.streamID) })?.streamID else {
            return nil
        }
        var out = Data()
        let base = data.startIndex
        for packet in packets where packet.streamID == videoID {
            if let payload = packet.payload {
                out.append(data[(base + payload.lowerBound)..<(base + payload.upperBound)])
            }
        }
        return out.isEmpty ? nil : out
    }

    /// The audio stream_ids (MPEG audio 0xC0-0xDF, and private_stream_1 0xBD, which
    /// carries AC-3 / LPCM in practice) of a Program Stream, in order of appearance.
    public static func mpeg2AudioStreamIDs(_ data: Data) -> [UInt8] {
        guard mpeg2SystemsLayer(data) != nil else { return [] }
        var seen: [UInt8] = []
        for packet in mpeg2SystemsPackets(data)
        where (0xC0...0xDF).contains(packet.streamID) || packet.streamID == 0xBD {
            if !seen.contains(packet.streamID) { seen.append(packet.streamID) }
        }
        return seen
    }
}
