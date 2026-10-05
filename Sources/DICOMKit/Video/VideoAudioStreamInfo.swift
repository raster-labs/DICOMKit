//
// VideoAudioStreamInfo.swift
// DICOMKit
//
// Copyright © 2026 DICOMKit. All rights reserved.
//

// Audio stream descriptions and the PS3.5 8.2.5 / 8.2.12 per-track rules the container parsers
// (MP4, MPEG-TS) and `VideoProbe` report. Merged from origin/main (PR #217) beside the richer
// `VideoAudioTrack` / `validateAudio` checks in VideoAudio.swift; both are kept.

import Foundation

/// An audio coding format, as far as the DICOM video rules distinguish them.
///
/// PS3.5 8.2.12 permits five formats alongside AVC and HEVC video, and 8.2.5
/// permits one alongside MPEG-2 video; everything else is reported by name so a
/// rejection can say what was found.
public enum AudioFormat: Sendable, Hashable {
    /// Linear PCM.
    case lpcm
    /// Dolby AC-3 (ETSI TS 102 366).
    case ac3
    /// MPEG-2 / MPEG-4 AAC (ISO/IEC 13818-7, 14496-3).
    case aac
    /// MPEG-1 Audio Layer III (ISO/IEC 11172-3).
    case mp3
    /// MPEG-1 Audio Layer II (ISO/IEC 11172-3).
    case mp2
    /// Any other format, named for the report.
    case other(String)

    /// A human-readable name for reports.
    public var displayName: String {
        switch self {
        case .lpcm: return "LPCM"
        case .ac3: return "AC-3"
        case .aac: return "AAC"
        case .mp3: return "MP3"
        case .mp2: return "MPEG-1 Layer II"
        case let .other(name): return name
        }
    }
}

/// What an audio track says about itself.
///
/// Every field is optional because containers disagree about what they record:
/// an MP4 sample entry always names the format, but a transport stream reveals
/// sample rate and channel layout only in the first frame header. A field that
/// could not be read is never treated as a violation - only a value that was
/// read and is wrong is.
public struct AudioStreamInfo: Sendable, Hashable {
    /// The coding format.
    public let format: AudioFormat
    /// Output sampling frequency in Hz.
    public let sampleRate: Int?
    /// Channel count, low-frequency channel included: 6 is 5.1.
    public let channels: Int?
    /// Bits per sample, where the format codes one (LPCM).
    public let bitsPerSample: Int?
    /// Average bit rate in bits per second.
    public let bitRate: Int?
    /// Whether every frame uses the same bit rate, where that can be judged.
    public let isConstantBitRate: Bool?

    public init(
        format: AudioFormat,
        sampleRate: Int? = nil,
        channels: Int? = nil,
        bitsPerSample: Int? = nil,
        bitRate: Int? = nil,
        isConstantBitRate: Bool? = nil
    ) {
        self.format = format
        self.sampleRate = sampleRate
        self.channels = channels
        self.bitsPerSample = bitsPerSample
        self.bitRate = bitRate
        self.isConstantBitRate = isConstantBitRate
    }

    /// A one-line summary, e.g. "AAC, 48 kHz, 2 ch, 128 kbps".
    public var summary: String {
        var parts = [format.displayName]
        if let rate = sampleRate { parts.append(Self.formatSampleRate(rate)) }
        if let channels = channels { parts.append(Self.formatChannels(channels)) }
        if let bits = bitsPerSample { parts.append("\(bits)-bit") }
        if let bitRate = bitRate { parts.append("\(Int((Double(bitRate) / 1000).rounded())) kbps") }
        if format == .mp3, let constant = isConstantBitRate {
            parts.append(constant ? "CBR" : "VBR")
        }
        return parts.joined(separator: ", ")
    }

    static func formatSampleRate(_ rate: Int) -> String {
        if rate % 1000 == 0 { return "\(rate / 1000) kHz" }
        return String(format: "%.1f kHz", Double(rate) / 1000)
    }

    static func formatChannels(_ channels: Int) -> String {
        channels == 6 ? "5.1 ch" : "\(channels) ch"
    }
}

// MARK: - DICOM Audio Rules

/// The audio constraints of PS3.5 8.2.5 (MPEG-2 video) and 8.2.12 (AVC and HEVC
/// video).
///
/// Audio is optional, and when present it is interleaved in the same container
/// as the video - so it travels inside the encapsulated Pixel Data, and has to
/// meet these rules for the object to be conformant.
public enum VideoAudioRules {

    /// Why an audio track breaks the rules for the video it accompanies.
    ///
    /// Each returned string completes the sentence "audio track N (...) ...".
    public static func problems(
        with audio: AudioStreamInfo,
        videoCodec: VideoCodec,
        container: VideoContainer
    ) -> [String] {
        switch videoCodec {
        case .mpeg2:
            return mpeg2Problems(audio)
        case .h264, .h265:
            return avcHEVCProblems(audio, container: container)
        case .unknown:
            return []
        }
    }

    /// PS3.5 8.2.5: CBR MPEG-1 Layer III only, at 32, 44.1 or 48 kHz, with one
    /// mono or stereo main channel.
    private static func mpeg2Problems(_ audio: AudioStreamInfo) -> [String] {
        guard audio.format == .mp3 else {
            return ["is \(audio.format.displayName); MPEG-2 video permits only CBR "
                    + "MPEG-1 Layer III (MP3) audio (PS3.5 8.2.5)"]
        }
        var problems: [String] = []
        if audio.isConstantBitRate == false {
            problems.append("is variable bit rate; MPEG-2 video requires CBR MP3 (PS3.5 8.2.5)")
        }
        problems += sampleRateProblems(audio, permitted: [32_000, 44_100, 48_000], section: "8.2.5")
        if let channels = audio.channels, channels > 2 {
            problems.append("has \(channels) channels; MPEG-2 video permits one mono or "
                            + "stereo main channel (PS3.5 8.2.5)")
        }
        return problems
    }

    /// PS3.5 Table 8.2.12-1 and the per-format limits that follow it.
    private static func avcHEVCProblems(
        _ audio: AudioStreamInfo,
        container: VideoContainer
    ) -> [String] {
        var problems: [String] = []
        let section = "PS3.5 8.2.12"

        switch audio.format {
        case .lpcm:
            if container != .mpegTS {
                problems.append("is LPCM, which is permitted only in an MPEG-2 Transport "
                                + "Stream, not \(container.displayName) (\(section))")
            }
            problems += bitRateProblems(audio, maximum: 4_608_000, section: "8.2.12")
            problems += sampleRateProblems(audio, permitted: [48_000, 96_000], section: "8.2.12")
            if let bits = audio.bitsPerSample, ![16, 20, 24].contains(bits) {
                problems.append("is \(bits)-bit; LPCM must be 16, 20 or 24-bit (\(section))")
            }
            if let channels = audio.channels, channels != 2 {
                problems.append("has \(channels) channels; LPCM must be 2-channel (\(section))")
            }
        case .ac3:
            if container != .mpegTS {
                problems.append("is AC-3, which is permitted only in an MPEG-2 Transport "
                                + "Stream, not \(container.displayName) (\(section))")
            }
            problems += bitRateProblems(audio, maximum: 640_000, section: "8.2.12")
            problems += sampleRateProblems(audio, permitted: [48_000], section: "8.2.12")
            problems += channelProblems(audio, permitted: [2, 6], name: "2 or 5.1", section: section)
        case .aac:
            problems += bitRateProblems(audio, maximum: 640_000, section: "8.2.12")
            problems += sampleRateProblems(audio, permitted: [48_000], section: "8.2.12")
            problems += channelProblems(audio, permitted: [2, 6], name: "2 or 5.1", section: section)
        case .mp3:
            problems += bitRateProblems(audio, maximum: 320_000, section: "8.2.12")
            problems += sampleRateProblems(audio, permitted: [32_000, 44_100, 48_000], section: "8.2.12")
            if audio.isConstantBitRate == false {
                problems.append("is variable bit rate; MP3 must be CBR (\(section))")
            }
            if let channels = audio.channels, channels > 2 {
                problems.append("has \(channels) channels; MP3 permits one mono or stereo "
                                + "main channel (\(section))")
            }
        case .mp2:
            problems += bitRateProblems(audio, maximum: 384_000, section: "8.2.12")
            problems += sampleRateProblems(audio, permitted: [32_000, 44_100, 48_000], section: "8.2.12")
            problems += channelProblems(audio, permitted: [2], name: "2", section: section)
        case let .other(name):
            problems.append("is \(name), which is not a permitted format; AVC and HEVC "
                            + "video permit LPCM, AC-3, AAC, MP3 or MPEG-1 Layer II (\(section))")
        }
        return problems
    }

    private static func bitRateProblems(
        _ audio: AudioStreamInfo,
        maximum: Int,
        section: String
    ) -> [String] {
        // Container-derived rates are averages over whole frames, so allow the
        // rounding of a frame's worth of bytes before calling a stream too fast.
        guard let bitRate = audio.bitRate, Double(bitRate) > Double(maximum) * 1.01 else { return [] }
        return ["runs at \(bitRate / 1000) kbps, above the \(maximum / 1000) kbps maximum "
                + "for \(audio.format.displayName) (PS3.5 \(section))"]
    }

    private static func sampleRateProblems(
        _ audio: AudioStreamInfo,
        permitted: [Int],
        section: String
    ) -> [String] {
        guard let rate = audio.sampleRate, !permitted.contains(rate) else { return [] }
        let names = permitted.map(AudioStreamInfo.formatSampleRate)
        let list = names.count == 1
            ? names[0]
            : names.dropLast().joined(separator: ", ") + " or " + names.last!
        return ["is sampled at \(AudioStreamInfo.formatSampleRate(rate)); "
                + "\(audio.format.displayName) must be \(list) (PS3.5 \(section))"]
    }

    private static func channelProblems(
        _ audio: AudioStreamInfo,
        permitted: Set<Int>,
        name: String,
        section: String
    ) -> [String] {
        guard let channels = audio.channels, !permitted.contains(channels) else { return [] }
        return ["has \(AudioStreamInfo.formatChannels(channels)); "
                + "\(audio.format.displayName) must have \(name) channels (\(section))"]
    }
}

// MARK: - Audio Header Parsing

/// Reads audio parameters from the frame headers and configuration records the
/// containers carry. These are the only places a transport stream states a
/// sample rate or channel layout.
extension AudioHeaderParser {

    // MARK: MPEG-1/2 Audio (Layers I-III)
    // The frame header itself is parsed by `mpegAudioHeader(_:at:)` in VideoAudio.swift.

    /// Describes an MPEG audio elementary stream from its leading frames.
    ///
    /// Constant bit rate is judged across every frame that can be walked: one
    /// bitrate index throughout means CBR.
    public static func describeMPEGAudio(_ data: Data) -> AudioStreamInfo? {
        let bytes = [UInt8](data)
        var offset = 0
        // Find the first header that is followed by another where its length
        // says it should be, so a stray 0xFFE in a payload is not mistaken.
        var first: MPEGAudioHeader?
        while offset + 4 <= bytes.count {
            if let header = mpegAudioHeader(bytes, at: offset) {
                if let length = header.frameLength, offset + length + 4 <= bytes.count {
                    if mpegAudioHeader(bytes, at: offset + length) != nil {
                        first = header
                        break
                    }
                } else {
                    first = header
                    break
                }
            }
            offset += 1
        }
        guard let header = first else { return nil }

        var indices: Set<Int> = []
        var totalBits = 0
        var frames = 0
        var cursor = offset
        while let frame = mpegAudioHeader(bytes, at: cursor), let length = frame.frameLength {
            indices.insert(frame.bitRateIndex)
            totalBits += frame.bitRate ?? 0
            frames += 1
            cursor += length
        }

        let format: AudioFormat
        switch header.layer {
        case 3: format = .mp3
        case 2: format = .mp2
        default: format = .other("MPEG-1 Layer I")
        }
        return AudioStreamInfo(
            format: format,
            sampleRate: header.samplingFrequency,
            channels: header.channelCount,
            bitRate: frames > 0 ? totalBits / frames : header.bitRate,
            isConstantBitRate: frames > 1 ? indices.count == 1 : nil
        )
    }

    // MARK: AAC

    /// Sampling frequencies indexed by `sampling_frequency_index`.
    static let aacSampleRates = [96_000, 88_200, 64_000, 48_000, 44_100, 32_000,
                                 24_000, 22_050, 16_000, 12_000, 11_025, 8_000, 7_350]

    /// Channel counts indexed by `channel_configuration`; 0 means "in a PCE".
    static let adtsChannelCounts = [0, 1, 2, 3, 4, 5, 6, 8]

    /// Describes an AAC stream from an MPEG-4 `AudioSpecificConfig`.
    ///
    /// With explicitly signalled SBR (HE-AAC), the output rate is the extension
    /// rate, which is what a listener - and the DICOM rule - sees.
    ///
    /// Reference: ISO/IEC 14496-3 Section 1.6.2.1
    public static func describeAudioSpecificConfig(_ config: Data) -> (sampleRate: Int?, channels: Int?) {
        var reader = BitstreamReader(bytes: [UInt8](config))

        func readObjectType() -> UInt32? {
            guard let type = reader.readBits(5) else { return nil }
            if type == 31 { return reader.readBits(6).map { 32 + $0 } }
            return type
        }
        func readSampleRate() -> Int? {
            guard let index = reader.readBits(4) else { return nil }
            if index == 15 { return reader.readBits(24).map(Int.init) }
            return Int(index) < aacSampleRates.count ? aacSampleRates[Int(index)] : nil
        }

        guard let objectType = readObjectType() else { return (nil, nil) }
        var sampleRate = readSampleRate()
        var channels: Int?
        if let configuration = reader.readBits(4), Int(configuration) < adtsChannelCounts.count,
           configuration > 0 {
            channels = adtsChannelCounts[Int(configuration)]
        }
        // SBR (5) or PS (29) signalled explicitly: the extension rate follows.
        if objectType == 5 || objectType == 29 {
            if let extensionRate = readSampleRate() { sampleRate = extensionRate }
            // Parametric stereo turns one coded channel into two.
            if objectType == 29, channels == 1 { channels = 2 }
        }
        return (sampleRate, channels)
    }

    /// Describes an ADTS-framed AAC stream from its leading frames.
    ///
    /// Reference: ISO/IEC 13818-7 Section 6.2 (adts_frame)
    public static func describeADTS(_ data: Data) -> AudioStreamInfo? {
        let bytes = [UInt8](data)
        var offset = 0
        while offset + 7 <= bytes.count, !(bytes[offset] == 0xFF && bytes[offset + 1] & 0xF6 == 0xF0) {
            offset += 1
        }
        guard offset + 7 <= bytes.count else { return nil }

        let sampleRateIndex = Int((bytes[offset + 2] >> 2) & 0x0F)
        guard sampleRateIndex < aacSampleRates.count else { return nil }
        let sampleRate = aacSampleRates[sampleRateIndex]
        let configuration = Int(((bytes[offset + 2] & 0x01) << 2) | (bytes[offset + 3] >> 6))
        let channels = configuration > 0 && configuration < adtsChannelCounts.count
            ? adtsChannelCounts[configuration] : nil

        // Average the frame lengths: each ADTS frame carries 1024 samples per
        // raw data block.
        var totalBytes = 0
        var totalSamples = 0
        var cursor = offset
        while cursor + 7 <= bytes.count, bytes[cursor] == 0xFF, bytes[cursor + 1] & 0xF6 == 0xF0 {
            let length = (Int(bytes[cursor + 3] & 0x03) << 11) | (Int(bytes[cursor + 4]) << 3)
                | Int(bytes[cursor + 5] >> 5)
            let blocks = Int(bytes[cursor + 6] & 0x03) + 1
            guard length >= 7, cursor + length <= bytes.count else { break }
            totalBytes += length
            totalSamples += 1024 * blocks
            cursor += length
        }
        let bitRate = totalSamples > 0
            ? Int(Double(totalBytes * 8) * Double(sampleRate) / Double(totalSamples))
            : nil
        return AudioStreamInfo(format: .aac, sampleRate: sampleRate, channels: channels, bitRate: bitRate)
    }

    // MARK: AC-3

    /// Describes an AC-3 stream from its first synchronization frame.
    ///
    /// Reference: ETSI TS 102 366 Sections 4.3.1 (syncinfo) and 4.3.2 (bsi)
    public static func describeAC3(_ data: Data) -> AudioStreamInfo? {
        let bytes = [UInt8](data)
        var offset = 0
        while offset + 8 <= bytes.count, !(bytes[offset] == 0x0B && bytes[offset + 1] == 0x77) {
            offset += 1
        }
        guard offset + 8 <= bytes.count else { return nil }

        let fscod = Int(bytes[offset + 4] >> 6)
        let frmsizecod = Int(bytes[offset + 4] & 0x3F)
        guard fscod < 3, frmsizecod < 38 else { return nil }
        let sampleRate = [48_000, 44_100, 32_000][fscod]
        let kbps = [32, 40, 48, 56, 64, 80, 96, 112, 128, 160, 192, 224, 256, 320,
                    384, 448, 512, 576, 640][frmsizecod >> 1]

        // bsi: bsid(5) bsmod(3) acmod(3), then mix levels that depend on acmod,
        // then lfeon.
        var reader = BitstreamReader(bytes: Array(bytes[(offset + 5)...]))
        guard reader.skipBits(8), let acmod = reader.readBits(3) else {
            return AudioStreamInfo(format: .ac3, sampleRate: sampleRate, bitRate: kbps * 1000)
        }
        if acmod & 0x01 != 0, acmod != 1 { _ = reader.skipBits(2) }   // cmixlev
        if acmod & 0x04 != 0 { _ = reader.skipBits(2) }               // surmixlev
        if acmod == 2 { _ = reader.skipBits(2) }                      // dsurmod
        let lfe = reader.readBit() == true ? 1 : 0
        let fullBandwidth = [2, 1, 2, 3, 3, 4, 4, 5][Int(acmod)]
        return AudioStreamInfo(
            format: .ac3,
            sampleRate: sampleRate,
            channels: fullBandwidth + lfe,
            bitRate: kbps * 1000
        )
    }

    // MARK: LPCM

    /// Describes a Blu-ray (HDMV) LPCM stream from its first PES payload header.
    ///
    /// Reference: Blu-ray Disc Read-Only Format Part 3, LPCM audio header
    public static func describeHDMVLPCM(_ data: Data) -> AudioStreamInfo? {
        let bytes = [UInt8](data.prefix(4))
        guard bytes.count == 4 else { return nil }
        let assignment = Int(bytes[2] >> 4)
        let frequency = Int(bytes[2] & 0x0F)
        let bitsCode = Int(bytes[3] >> 6)

        let channelsByAssignment = [1: 1, 3: 2, 4: 3, 5: 3, 6: 4, 7: 4, 8: 5, 9: 6, 10: 7, 11: 8]
        let rateByCode = [1: 48_000, 4: 96_000, 5: 192_000]
        let bitsByCode = [1: 16, 2: 20, 3: 24]
        guard let channels = channelsByAssignment[assignment],
              let sampleRate = rateByCode[frequency],
              let bits = bitsByCode[bitsCode]
        else { return AudioStreamInfo(format: .lpcm) }

        // HDMV pads odd channel counts to even, so the carried rate does too.
        let carriedChannels = channels + channels % 2
        return AudioStreamInfo(
            format: .lpcm,
            sampleRate: sampleRate,
            channels: channels,
            bitsPerSample: bits,
            bitRate: carriedChannels * bits * sampleRate
        )
    }
}

// MARK: - Bridge to VideoAudioTrack

extension VideoAudioTrack {

    /// The track as a plain stream description, the form ``VideoAudioRules`` and
    /// ``VideoConsole/audioCarriedLine(_:)`` take.
    public var streamInfo: AudioStreamInfo {
        let audioFormat: AudioFormat
        switch format {
        case .some(.lpcm): audioFormat = .lpcm
        case .some(.ac3): audioFormat = .ac3
        case .some(.aac): audioFormat = .aac
        case .some(.mp3): audioFormat = .mp3
        case .some(.mpeg1LayerII): audioFormat = .mp2
        case let .some(other): audioFormat = .other(other.rawValue)
        case .none: audioFormat = .other("unidentified '\(codecTag)'")
        }
        return AudioStreamInfo(
            format: audioFormat,
            sampleRate: samplingFrequency,
            channels: channelCount,
            bitsPerSample: bitsPerSample,
            bitRate: averageBitRate ?? frameBitRate ?? maximumBitRate,
            isConstantBitRate: bitRateScan?.isConstant
        )
    }

    /// A track built from a plain stream description; the codec tag names the origin.
    public init(_ info: AudioStreamInfo) {
        let format: Format
        switch info.format {
        case .lpcm: format = .lpcm
        case .ac3: format = .ac3
        case .aac: format = .aac
        case .mp3: format = .mp3
        case .mp2: format = .mpeg1LayerII
        case let .other(name): format = Format(rawValue: name)
        }
        self.init(
            format: format, codecTag: "stream info",
            samplingFrequency: info.sampleRate, channelCount: info.channels,
            bitsPerSample: info.bitsPerSample, averageBitRate: info.bitRate)
    }
}
