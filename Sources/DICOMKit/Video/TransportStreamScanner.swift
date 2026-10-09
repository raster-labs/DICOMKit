// NEMA-verified: 2026a, checked 2026-09-30 — ADTS and LATM PIDs are read up to 2,000 frames for the Table 8.2.12-1 bit rate (PS3.5 2026a 8.2.12, D62); the MPEG-4_audio_extension_descriptor (tag 0x2E) syntax matches TSDuck's tsMPEG4AudioExtensionDescriptor.cpp and tsDID.h (ISO/IEC 13818-1 is not NEMA text)
// NEMA-verified: 2026a, checked 2026-09-30 — MP3 frame headers walked for "CBR MPEG-1 LAYER III" (PS3.5 2026a 8.2.5, 8.2.12, verified by script); LATM/LOAS (stream_type 0x11) and raw MPEG-4 audio (0x1C) identified from the AudioSpecificConfig (ISO/IEC 14496-3, ISO/IEC 13818-1; out of DICOM scope) (D58)
// NEMA-verified: 2026a, checked 2026-09-30 — transport stream syntax is ISO/IEC 13818-1 (out of scope); audio PIDs are identified for the PS3.5 2026a 8.2.5/8.2.12 check (Table 8.2.12-1 permits LPCM, AC-3, AAC, MP3 and MPEG-1 Layer II in MPEG-2 TS) (D46)
//
// TransportStreamScanner.swift
// DICOMKit
//
// Copyright © 2026 DICOMKit. All rights reserved.
//

import Foundation

/// Reads the elementary streams of an MPEG-2 Transport Stream.
///
/// ``demux(_:)`` reassembles the video PID in full - enough to read its
/// parameter sets, count its pictures and recover its timing from the PES
/// timestamps - and the head of each audio PID, which is where a transport
/// stream states its audio format. PS3.5 blesses MPEG-TS as one of the two
/// containers, so it is validated exactly like MP4 rather than taken on trust.
///
/// ``firstVideoPayload(_:)`` remains for the `--trust-input` path, which needs
/// geometry for Rows and Columns but nothing else.
///
/// Audio PIDs are listed from the PMT, and the first frame of each is read for the
/// parameters PS3.5 8.2.12 constrains (``audioTracks(_:)``).
///
/// Reference: ISO/IEC 13818-1 Sections 2.4.3.2 (packet layer), 2.4.3.6 (PES)
public enum TransportStreamScanner {

    /// The fixed TS packet length. The 192- and 204-byte variants carry the same
    /// 188-byte packet with extra framing, which `packetStride` detects.
    private static let packetSize = 188

    /// How many bytes of elementary stream to gather before giving up. A sequence
    /// header sits near the start of the first GOP, so a small budget suffices and
    /// keeps a large file from being walked in full.
    private static let payloadBudget = 512 * 1024

    /// Stream type values that identify a video PID in the PMT, mapped to the
    /// codec each denotes.
    ///
    /// The PMT is the authority on codec here. Sniffing the payload instead would
    /// misidentify it: MPEG-2 start codes share the Annex B prefix, so an MPEG-2
    /// sequence header can parse as a plausible — and wrong — H.264 SPS.
    ///
    /// Reference: ISO/IEC 13818-1 Table 2-34
    private static let videoStreamTypes: [UInt8: VideoCodec] = [
        0x01: .mpeg2,  // MPEG-1 video, which the MPEG-2 parser also reads
        0x02: .mpeg2,
        0x1B: .h264,
        0x24: .h265,
    ]

    /// The first video PID's leading elementary-stream bytes and declared codec.
    public struct VideoPayload: Sendable {
        /// Concatenated PES payload, starting at a PES boundary.
        public let data: Data
        /// The codec the PMT declares for this PID.
        public let codec: VideoCodec
    }

    // MARK: - Demux

    /// What a transport stream carries, as far as validation needs it.
    public struct Demuxed: Sendable {
        /// The codec the PMT declares for the video PID.
        public let codec: VideoCodec
        /// The whole video elementary stream, PES headers removed.
        public let videoElementaryStream: Data
        /// Presentation timestamps of the video PES packets, in stream order, in
        /// 90 kHz ticks. Bounded: enough to recover a frame interval.
        public let presentationTimestamps: [UInt64]
        /// The audio PIDs, described from their first frames.
        public let audio: [VideoAudioTrack]
        /// The head of an MVC dependent-view sub-bitstream (stream_type 0x20),
        /// when the program carries one; its subset SPS reveals Stereo High.
        public let mvcSubBitstream: Data?
    }

    /// Demultiplexes the first program's video PID and audio PIDs.
    ///
    /// - Returns: The streams, or nil when there is no readable video PID.
    public static func demux(_ data: Data) -> Demuxed? {
        guard let layout = packetLayout(data) else { return nil }
        let streams = programStreams(data, layout: layout)
        guard let video = streams.first(where: { videoStreamTypes[$0.streamType] != nil }),
              let codec = videoStreamTypes[video.streamType]
        else { return nil }

        let mvc = streams.first { $0.streamType == mvcSubBitstreamType }

        var budgets: [Int: Int] = [video.pid: Int.max]
        if let mvc = mvc { budgets[mvc.pid] = payloadBudget }

        let collected = collect(data, layout: layout, budgets: budgets, timestampPID: video.pid)
        guard let videoData = collected.payloads[video.pid], !videoData.isEmpty else { return nil }

        // Audio is described by `audioTracks(_:)`, which reads each PID's own head and walks
        // MP3 / AAC frames for the bit rate checks of PS3.5 8.2.5 / 8.2.12.
        let audio = audioTracks(data)
        return Demuxed(
            codec: codec,
            videoElementaryStream: videoData,
            presentationTimestamps: collected.timestamps,
            audio: audio,
            mvcSubBitstream: mvc.flatMap { collected.payloads[$0.pid] }
        )
    }

    /// The frame rate implied by a run of PES presentation timestamps: 90 kHz
    /// over the most common gap between consecutive pictures in display order.
    ///
    /// The mode, not the mean, so that a dropped packet or a discontinuity does
    /// not skew it.
    public static func frameRate(fromTimestamps timestamps: [UInt64]) -> Double? {
        let sorted = Array(Set(timestamps)).sorted()
        guard sorted.count >= 3 else { return nil }
        var counts: [UInt64: Int] = [:]
        for (earlier, later) in zip(sorted, sorted.dropFirst()) {
            let gap = later - earlier
            if gap > 0, gap < 90_000 { counts[gap, default: 0] += 1 }
        }
        guard let gap = counts.max(by: { $0.value < $1.value || ($0.value == $1.value && $0.key > $1.key) })?.key
        else { return nil }
        let rate = 90_000.0 / Double(gap)
        return rate.isFinite && rate > 0 && rate < 1000 ? rate : nil
    }

    /// stream_type of an MVC video sub-bitstream (ISO/IEC 13818-1 Table 2-34).
    private static let mvcSubBitstreamType: UInt8 = 0x20

    /// How much of each audio PID to read: a few dozen frames is enough to
    /// judge a format, its rate and whether its bit rate is constant.

    /// The leading elementary-stream bytes of the first video PID.
    ///
    /// - Parameter data: The transport stream.
    /// - Returns: The payload and its declared codec, or nil when no video PID is
    ///   found or it carries nothing readable.
    public static func firstVideoPayload(_ data: Data) -> VideoPayload? {
        guard let layout = packetLayout(data) else { return nil }
        guard let track = videoPID(data, layout: layout) else { return nil }
        guard let payload = payload(data, layout: layout, pid: track.pid) else { return nil }
        return VideoPayload(data: payload, codec: track.codec)
    }

    // MARK: - Packet Layout

    /// Where the first packet starts and how far apart packets are.
    private struct Layout {
        let start: Int
        let stride: Int
    }

    /// Determines the packet alignment, tolerating a leading partial packet and
    /// the 192-byte (timestamped) and 204-byte (error-corrected) framings.
    private static func packetLayout(_ data: Data) -> Layout? {
        for stride in [packetSize, 192, 204] {
            let searchLimit = min(stride, max(data.count - stride * 3, 0))
            guard searchLimit > 0 else { continue }
            for start in 0..<searchLimit {
                guard byte(data, at: start) == 0x47 else { continue }
                // Three further syncs at the same spacing rule out a stray 0x47.
                let confirmed = (1...3).allSatisfy { index in
                    byte(data, at: start + stride * index) == 0x47
                }
                if confirmed { return Layout(start: start, stride: stride) }
            }
        }
        return nil
    }

    // MARK: - PID Discovery

    /// One elementary stream entry of a PMT.
    private struct StreamEntry {
        let streamType: UInt8
        let pid: Int
        /// The ES_info descriptors, as (tag, payload).
        let descriptors: [(tag: UInt8, payload: [UInt8])]
        /// The program_info descriptors of the PMT that lists it.
        let programDescriptors: [(tag: UInt8, payload: [UInt8])]

        /// format_identifier values of registration descriptors (tag 0x05,
        /// ISO/IEC 13818-1 2.6.8) at stream or program level.
        var registrations: Set<String> {
            Set((descriptors + programDescriptors).compactMap { descriptor in
                guard descriptor.tag == 0x05, descriptor.payload.count >= 4 else { return nil }
                return String(bytes: descriptor.payload.prefix(4), encoding: .ascii)
            })
        }

        func hasDescriptor(_ tag: UInt8) -> Bool { descriptors.contains { $0.tag == tag } }
    }

    /// Every elementary stream listed by the PMTs the PAT points to, in order.
    private static func programStreams(_ data: Data, layout: Layout) -> [StreamEntry] {
        let pat = section(data, layout: layout, pid: 0x0000, tableID: 0x00)
        guard !pat.isEmpty else { return [] }

        // PAT entries are program_number (2) + PMT PID (2), after an 8-byte header
        // and before the 4-byte CRC.
        var pmtPIDs: [Int] = []
        var offset = 8
        while offset + 4 <= pat.count - 4 {
            let programNumber = (Int(pat[offset]) << 8) | Int(pat[offset + 1])
            let pid = ((Int(pat[offset + 2]) & 0x1F) << 8) | Int(pat[offset + 3])
            // Program 0 designates the NIT, which carries no elementary streams.
            if programNumber != 0 { pmtPIDs.append(pid) }
            offset += 4
        }

        var entries: [StreamEntry] = []
        for pmtPID in pmtPIDs {
            let pmt = section(data, layout: layout, pid: pmtPID, tableID: 0x02)
            guard !pmt.isEmpty else { continue }
            // Skip the 12-byte header, then the program_info descriptors.
            guard pmt.count > 12 else { continue }
            let programInfoLength = ((Int(pmt[10]) & 0x0F) << 8) | Int(pmt[11])
            let programDescriptors = descriptors(pmt, from: 12, length: programInfoLength)
            var entry = 12 + programInfoLength
            while entry + 5 <= pmt.count - 4 {
                let streamType = pmt[entry]
                let pid = ((Int(pmt[entry + 1]) & 0x1F) << 8) | Int(pmt[entry + 2])
                let esInfoLength = ((Int(pmt[entry + 3]) & 0x0F) << 8) | Int(pmt[entry + 4])
                entries.append(StreamEntry(
                    streamType: streamType, pid: pid,
                    descriptors: descriptors(pmt, from: entry + 5, length: esInfoLength),
                    programDescriptors: programDescriptors))
                entry += 5 + esInfoLength
            }
        }
        return entries
    }

    /// Splits a descriptor loop into (tag, payload) pairs.
    private static func descriptors(
        _ bytes: [UInt8], from start: Int, length: Int
    ) -> [(tag: UInt8, payload: [UInt8])] {
        var result: [(tag: UInt8, payload: [UInt8])] = []
        var offset = start
        let end = min(start + length, bytes.count)
        while offset + 2 <= end {
            let tag = bytes[offset]
            let size = Int(bytes[offset + 1])
            guard offset + 2 + size <= end else { break }
            result.append((tag, Array(bytes[(offset + 2)..<(offset + 2 + size)])))
            offset += 2 + size
        }
        return result
    }

    /// Finds the first video PID by reading the PAT, then the PMT it points to.
    ///
    /// Falls back to nil rather than guessing: encapsulating the wrong PID would
    /// describe the object with another track's geometry.
    private static func videoPID(_ data: Data, layout: Layout) -> (pid: Int, codec: VideoCodec)? {
        for entry in programStreams(data, layout: layout) {
            if let codec = videoStreamTypes[entry.streamType] { return (entry.pid, codec) }
        }
        return nil
    }

    // MARK: - Audio

    /// How many bytes of each audio PID to read for its first frame header.
    private static let audioPayloadBudget = 16 * 1024

    /// How many bytes of an MP3 PID to read for the constant-bit-rate walk: enough
    /// for ``AudioHeaderParser/maximumScannedFrames`` of the largest Layer III
    /// frame (1,441 bytes: 320 kbit/s at 32 kHz), so the frame bound, not the byte
    /// budget, ends the walk of a long stream; a short one is read whole.
    private static let mp3ScanBudget = AudioHeaderParser.maximumScannedFrames * 1441 + 4

    /// How many bytes of an AAC PID to read for the bit rate walk (D62): enough for
    /// ``AudioHeaderParser/maximumScannedFrames`` of the largest ADTS frame or LOAS
    /// element (13-bit lengths, 8,191 bytes plus a 3-byte LOAS header).
    private static let aacScanBudget = AudioHeaderParser.maximumScannedFrames * 8194

    /// The audio streams a transport stream's PMTs list, with the parameters
    /// read from each stream's first frame where the format makes that simple.
    ///
    /// Identification follows the PMT stream_type (ISO/IEC 13818-1 Table 2-34):
    /// 0x03 MPEG-1 audio and 0x04 MPEG-2 audio (layer from the frame header; for
    /// Layer III every frame header is then walked for the CBR rule, see
    /// ``AudioHeaderParser/scanMPEGAudioFrames(_:)``), 0x0F AAC with ADTS, 0x11
    /// MPEG-4 audio in LATM/LOAS (ISO/IEC 14496-3 1.7; the AudioSpecificConfig of
    /// its StreamMuxConfig, common case), 0x1C raw MPEG-4 audio (the
    /// AudioSpecificConfig of an MPEG-4_audio_extension_descriptor, when present). Values from 0x80 are "User Private" in 13818-1
    /// and are read as their registering systems define them: 0x81 AC-3 and 0x87
    /// E-AC-3 (ATSC A/52 and A/53, also used by Blu-ray); and, only in a
    /// stream carrying the "HDMV" registration descriptor (Blu-ray), 0x80 LPCM,
    /// 0x82/0x85/0x86 DTS, 0x83 Dolby TrueHD, 0x84 E-AC-3. stream_type 0x06
    /// (PES private data) is audio only with a DVB AC-3 (0x6A), enhanced AC-3
    /// (0x7A), DTS (0x7B) or AAC (0x7C) descriptor (ETSI EN 300 468), or an
    /// "AC-3", "EAC3", "Opus" or "BSSD" (SMPTE ST 302 LPCM) registration.
    ///
    /// - Returns: The audio tracks in PMT order; empty when there are none or the
    ///   PAT/PMT cannot be read.
    public static func audioTracks(_ data: Data) -> [VideoAudioTrack] {
        guard let layout = packetLayout(data) else { return [] }
        var seen: Set<Int> = []
        var tracks: [VideoAudioTrack] = []
        for entry in programStreams(data, layout: layout) where !seen.contains(entry.pid) {
            guard let kind = audioKind(entry) else { continue }
            seen.insert(entry.pid)
            let tag = String(format: "stream_type 0x%02X", entry.streamType)
            let bytes = payload(data, layout: layout, pid: entry.pid, budget: audioPayloadBudget)
                .map { [UInt8]($0) } ?? []
            var parsed: VideoAudioTrack?
            switch kind {
            case .mpegAudio:
                parsed = AudioHeaderParser.findMPEGAudioHeader(bytes)?.track(codecTag: tag)
                if parsed?.format == .mp3 {
                    let stream = payload(data, layout: layout, pid: entry.pid, budget: mp3ScanBudget)
                        .map { [UInt8]($0) } ?? []
                    parsed = parsed?.with(bitRateScan: AudioHeaderParser.scanMPEGAudioFrames(stream))
                }
            case .latm:
                parsed = AudioHeaderParser.findLATMConfig(bytes)
                if parsed != nil {
                    let (stream, complete) = aacStream(data, layout: layout, pid: entry.pid)
                    parsed = parsed?.with(measuredBitRate:
                        AudioHeaderParser.scanLATMBitRate(stream, complete: complete))
                }
            case .mpeg4Raw:
                parsed = entry.descriptors.lazy.filter { $0.tag == 0x2E }
                    .compactMap { AudioHeaderParser.mpeg4AudioExtensionDescriptor($0.payload) }.first
            case .adts:
                parsed = AudioHeaderParser.findADTSHeader(bytes)
                if parsed != nil {
                    let (stream, complete) = aacStream(data, layout: layout, pid: entry.pid)
                    parsed = parsed?.with(measuredBitRate:
                        AudioHeaderParser.scanADTSBitRate(stream, complete: complete))
                }
            case .ac3: parsed = AudioHeaderParser.findAC3Header(bytes)
            case .hdmvLPCM: parsed = AudioHeaderParser.hdmvLPCM(bytes)
            case .smpte302: parsed = AudioHeaderParser.smpte302(bytes)
            case let .named(format):
                parsed = VideoAudioTrack(format: format, codecTag: tag)
            }
            let fallback = VideoAudioTrack(format: kind.format, codecTag: tag)
            tracks.append((parsed ?? fallback).with(codecTag: tag, pid: entry.pid))
        }
        return tracks
    }

    /// An AAC PID's elementary stream for the bit rate walk, and whether it was read
    /// whole (the budget was not reached).
    private static func aacStream(_ data: Data, layout: Layout, pid: Int) -> ([UInt8], Bool) {
        let stream = payload(data, layout: layout, pid: pid, budget: aacScanBudget).map { [UInt8]($0) } ?? []
        return (stream, stream.count < aacScanBudget)
    }

    /// How an audio stream is identified and read.
    private enum AudioKind {
        case mpegAudio, adts, ac3, hdmvLPCM, smpte302, latm, mpeg4Raw
        /// Identified, but its header is not read (or it is not identifiable:
        /// a nil format).
        case named(VideoAudioTrack.Format?)

        /// The format known from the PMT alone.
        var format: VideoAudioTrack.Format? {
            switch self {
            case .mpegAudio: return nil  // Layer I, II or III: only the frame says
            case .latm, .mpeg4Raw: return nil  // any MPEG-4 audio object type
            case .adts: return .aac
            case .ac3: return .ac3
            case .hdmvLPCM, .smpte302: return .lpcm
            case let .named(format): return format
            }
        }
    }

    /// The audio kind a PMT entry declares, or nil when it is not audio.
    private static func audioKind(_ entry: StreamEntry) -> AudioKind? {
        let registrations = entry.registrations
        let isHDMV = registrations.contains("HDMV")
        switch entry.streamType {
        case 0x03, 0x04: return .mpegAudio
        case 0x0F: return .adts
        case 0x11: return .latm
        case 0x1C: return .mpeg4Raw
        case 0x81: return .ac3
        case 0x87: return .named(.eac3)
        case 0x80 where isHDMV: return .hdmvLPCM
        case 0x82 where isHDMV, 0x85 where isHDMV, 0x86 where isHDMV: return .named(.dts)
        case 0x83 where isHDMV: return .named(.trueHD)
        case 0x84 where isHDMV: return .named(.eac3)
        case 0x06:
            if entry.hasDescriptor(0x6A) || registrations.contains("AC-3") { return .ac3 }
            if entry.hasDescriptor(0x7A) || registrations.contains("EAC3") { return .named(.eac3) }
            if entry.hasDescriptor(0x7B) { return .named(.dts) }
            if entry.hasDescriptor(0x7C) { return .adts }
            if registrations.contains("Opus") { return .named(.opus) }
            if registrations.contains("BSSD") { return .smpte302 }
            return nil
        default: return nil
        }
    }

    /// Reassembles one PSI section carrying the given table ID.
    ///
    /// Sections begin at the pointer_field offset of a packet flagged as a payload
    /// start, and may continue across packets.
    private static func section(
        _ data: Data,
        layout: Layout,
        pid targetPID: Int,
        tableID: UInt8
    ) -> [UInt8] {
        var section: [UInt8] = []
        var expected: Int?

        forEachPacket(data, layout: layout) { packet in
            guard pid(of: packet) == targetPID, let body = packetPayload(packet) else {
                return true
            }

            var bytes = body
            if payloadStarts(packet) {
                // A pointer_field leads the payload, giving the offset of the
                // first section byte.
                guard let pointer = bytes.first else { return true }
                let sectionStart = 1 + Int(pointer)
                guard sectionStart < bytes.count else { return true }
                bytes = Array(bytes[sectionStart...])
                guard bytes.first == tableID else { return true }
                section = []
                expected = nil
            } else if section.isEmpty {
                // Mid-section packet with no start seen yet: nothing to append to.
                return true
            }

            section += bytes
            if expected == nil, section.count >= 3 {
                // section_length counts the bytes after its own field.
                expected = (((Int(section[1]) & 0x0F) << 8) | Int(section[2])) + 3
            }
            if let total = expected, section.count >= total {
                section = Array(section.prefix(total))
                return false
            }
            return true
        }

        guard let total = expected, section.count >= total else { return [] }
        return section
    }

    // MARK: - Payload Assembly

    /// Concatenates the PES payloads of several PIDs in one pass, each up to its
    /// byte budget, and records the PTS of one PID's PES packets.
    private static func collect(
        _ data: Data,
        layout: Layout,
        budgets: [Int: Int],
        timestampPID: Int
    ) -> (payloads: [Int: Data], timestamps: [UInt64]) {
        var payloads: [Int: Data] = [:]
        var timestamps: [UInt64] = []
        var finished: Set<Int> = []

        forEachPacket(data, layout: layout) { packet in
            let packetPID = pid(of: packet)
            guard let budget = budgets[packetPID], !finished.contains(packetPID),
                  let body = packetPayload(packet)
            else { return true }

            var bytes = body[...]
            if payloadStarts(packet) {
                if bytes.count >= 9, bytes[bytes.startIndex] == 0x00,
                   bytes[bytes.startIndex + 1] == 0x00, bytes[bytes.startIndex + 2] == 0x01 {
                    let base = bytes.startIndex
                    let headerLength = Int(bytes[base + 8])
                    if packetPID == timestampPID, timestamps.count < maxTimestamps,
                       bytes[base + 7] & 0x80 != 0, bytes.count >= 14 {
                        timestamps.append(presentationTimestamp(Array(bytes[(base + 9)..<(base + 14)])))
                    }
                    let elementaryStart = base + 9 + headerLength
                    guard elementaryStart <= bytes.endIndex else { return true }
                    bytes = bytes[elementaryStart...]
                }
            } else if payloads[packetPID] == nil {
                // Wait for a payload start, so each stream begins at a PES boundary.
                return true
            }

            payloads[packetPID, default: Data()].append(contentsOf: bytes)
            if let count = payloads[packetPID]?.count, count >= budget {
                finished.insert(packetPID)
            }
            return finished.count < budgets.count
        }
        return (payloads, timestamps)
    }

    /// How many PTS values to keep: enough for a stable frame interval.
    private static let maxTimestamps = 512

    /// Decodes a 33-bit PTS from its five-byte, marker-interleaved form.
    private static func presentationTimestamp(_ bytes: [UInt8]) -> UInt64 {
        let high = UInt64((bytes[0] >> 1) & 0x07) << 30
        let middle = ((UInt64(bytes[1]) << 8 | UInt64(bytes[2])) >> 1) << 15
        let low = (UInt64(bytes[3]) << 8 | UInt64(bytes[4])) >> 1
        return high | middle | low
    }

    /// Concatenates the PES payloads of one PID, up to the byte budget.
    private static func payload(
        _ data: Data, layout: Layout, pid targetPID: Int, budget: Int = payloadBudget
    ) -> Data? {
        var payload = Data()

        forEachPacket(data, layout: layout) { packet in
            guard pid(of: packet) == targetPID, let body = packetPayload(packet) else {
                return true
            }

            var bytes = body
            if payloadStarts(packet) {
                // Strip the PES header so the elementary stream starts clean; a
                // packet without the start-code prefix is passed through as-is.
                if bytes.count >= 9, bytes[0] == 0x00, bytes[1] == 0x00, bytes[2] == 0x01 {
                    let headerLength = Int(bytes[8])
                    let elementaryStart = 9 + headerLength
                    guard elementaryStart <= bytes.count else { return true }
                    bytes = Array(bytes[elementaryStart...])
                }
            } else if payload.isEmpty {
                // Wait for a payload start, so the stream begins at a PES boundary.
                return true
            }

            payload.append(contentsOf: bytes)
            return payload.count < budget
        }

        return payload.isEmpty ? nil : payload
    }

    // MARK: - Packet Fields

    /// Walks packets in order, stopping when the body returns false.
    private static func forEachPacket(
        _ data: Data,
        layout: Layout,
        body: ([UInt8]) -> Bool
    ) {
        var offset = layout.start
        while offset + packetSize <= data.count {
            guard byte(data, at: offset) == 0x47 else {
                // Resynchronize rather than abandoning the rest of the file.
                offset += 1
                continue
            }
            let base = data.startIndex + offset
            let packet = [UInt8](data[base..<(base + packetSize)])
            if !body(packet) { return }
            offset += layout.stride
        }
    }

    /// The 13-bit PID from a packet header.
    private static func pid(of packet: [UInt8]) -> Int {
        ((Int(packet[1]) & 0x1F) << 8) | Int(packet[2])
    }

    /// Whether the packet begins a new PES packet or PSI section.
    private static func payloadStarts(_ packet: [UInt8]) -> Bool {
        packet[1] & 0x40 != 0
    }

    /// The packet's payload, with any adaptation field removed.
    ///
    /// Returns nil for a packet that carries no payload, or one that is scrambled
    /// and so cannot be read.
    private static func packetPayload(_ packet: [UInt8]) -> [UInt8]? {
        // transport_scrambling_control occupies the top two bits of byte 3.
        guard packet[3] & 0xC0 == 0 else { return nil }

        let adaptationControl = (packet[3] >> 4) & 0x03
        // 0 is reserved, 2 is adaptation field only: neither carries payload.
        guard adaptationControl == 1 || adaptationControl == 3 else { return nil }

        var start = 4
        if adaptationControl == 3 {
            let adaptationLength = Int(packet[4])
            start = 5 + adaptationLength
            guard start <= packet.count else { return nil }
        }
        guard start < packet.count else { return nil }
        return Array(packet[start...])
    }

    /// Reads one byte at a file offset, tolerating a non-zero start index.
    private static func byte(_ data: Data, at offset: Int) -> UInt8? {
        guard offset >= 0, offset < data.count else { return nil }
        return data[data.startIndex + offset]
    }
}
