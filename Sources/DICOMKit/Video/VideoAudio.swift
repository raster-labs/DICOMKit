// NEMA-verified: 2026a, checked 2026-09-30 — MP3 dual channel mode is refused as neither the mono nor the stereo main channel of PS3.5 2026a 8.2.5 / 8.2.12, read in the MPEG-1 Part 3 modes those sections name (D61); AAC in MPEG-TS is measured against the 640 kbit/s of Table 8.2.12-1 over one-second windows from its ADTS / LOAS frames (D62; ADTS, LATM and AudioSpecificConfig field layouts checked against FFmpeg adts_header.c, aacdec_latm.h, mpeg4audio.c — ISO/IEC 13818-7 / 14496-3 are not NEMA text)
// NEMA-verified: 2026a, checked 2026-09-30 — D58: "CBR MPEG-1 LAYER III (MP3)" (PS3.5 2026a 8.2.5 and 8.2.12) checked by walking frame bitrate_index values (ISO/IEC 11172-3, 13818-3); "Bits per sample" of AAC/AC-3/MP3/MP2 not in the coded stream (ISO/IEC 13818-7, 14496-3, ETSI TS 102 366, ISO/IEC 11172-3), stated rather than reported; "optionally one or more complementary channel(s)" (ISO/IEC 13818-3 multichannel extension) not identifiable, kept "not checked"; LATM StreamMuxConfig and MPEG-4_audio_extension_descriptor AudioSpecificConfig (ISO/IEC 14496-3, 13818-1); PS3.5 text verified by script
// NEMA-verified: 2026a, checked 2026-09-30 — audio constraints extracted by script from PS3.5 2026a 8.2.5 (MPEG2 MP@ML; 8.2.6 MP@HL refers to it), 8.2.7-8.2.11 ("shall follow the constraints detailed in 8.2.12") and 8.2.12 with Table 8.2.12-1 (LPCM/AC-3 MPEG-2 TS only; AAC, MP3, MPEG-1 Layer II in MP4 or MPEG-2 TS); header syntax per ISO/IEC 11172-3, 13818-3, 13818-7, 14496-3, 14496-12/-14 and ETSI TS 102 366 (out of DICOM scope) (D46)
// NEMA-verified: 2026a, checked 2026-09-30 — E-AC-3 judged by the AC-3 row of PS3.5 2026a Table 8.2.12-1: 8.2.12 "AC-3 is standardized in" ETSI TS 102 366, whose PS3.5 bibliography entry is "Audio Compression (AC-3, Enhanced AC-3) Standard" (D59)
//
// VideoAudio.swift
// DICOMKit
//
// Copyright © 2026 DICOMKit. All rights reserved.
//

import Foundation
import DICOMCore

// MARK: - Audio Track

/// One audio track found in a video input's container, with whatever parameters
/// the container or the first audio frame expose.
///
/// Every parameter is optional: a value this toolkit could not read is nil, and
/// the PS3.5 8.2.5 / 8.2.12 check then reports that constraint as "not checked"
/// rather than as a violation.
public struct VideoAudioTrack: Sendable, Hashable {

    /// An audio coding format.
    ///
    /// A string-backed value rather than an enum, so formats can be named without
    /// adding cases to a public enum. The five formats PS3.5 8.2.12 lists, and the
    /// one 8.2.5 lists, have constants; anything else is identified by name so a
    /// report can say what it was.
    public struct Format: RawRepresentable, Sendable, Hashable, CustomStringConvertible {
        public let rawValue: String
        public init(rawValue: String) { self.rawValue = rawValue }
        public var description: String { rawValue }

        /// Linear PCM.
        public static let lpcm = Format(rawValue: "LPCM")
        /// Dolby AC-3 (ETSI TS 102 366).
        public static let ac3 = Format(rawValue: "AC-3")
        /// AAC (ISO/IEC 13818-7, or ISO/IEC 14496-3 Subpart 4).
        public static let aac = Format(rawValue: "AAC")
        /// MPEG-1 (or MPEG-2 LSF) Audio Layer III (ISO/IEC 11172-3, 13818-3).
        public static let mp3 = Format(rawValue: "MP3")
        /// MPEG-1 (or MPEG-2 LSF) Audio Layer II (ISO/IEC 11172-3, 13818-3).
        public static let mpeg1LayerII = Format(rawValue: "MPEG-1 Layer II")
        /// MPEG Audio Layer I — not listed by PS3.5.
        public static let mpegLayerI = Format(rawValue: "MPEG Audio Layer I")
        /// Enhanced AC-3 (ETSI TS 102 366 Annex E). PS3.5 8.2.12 names "AC-3" and
        /// cites ETSI TS 102 366, which the PS3.5 bibliography titles "Audio
        /// Compression (AC-3, Enhanced AC-3) Standard"; ``VideoConformanceValidator``
        /// therefore checks E-AC-3 against the AC-3 row of Table 8.2.12-1 (D59).
        public static let eac3 = Format(rawValue: "E-AC-3")
        /// DTS — not listed by PS3.5.
        public static let dts = Format(rawValue: "DTS")
        /// Dolby TrueHD — not listed by PS3.5.
        public static let trueHD = Format(rawValue: "Dolby TrueHD")
        /// Opus — not listed by PS3.5.
        public static let opus = Format(rawValue: "Opus")
    }

    /// The format, or nil when the container names none this toolkit recognises
    /// (for example an `mp4a` sample entry with no `esds`).
    public let format: Format?
    /// Where the format came from: an MP4 sample entry's four-character code
    /// (e.g. "mp4a", "ac-3") or an MPEG-TS stream type (e.g. "stream_type 0x0F").
    public let codecTag: String
    /// The MPEG-TS PID carrying the track; nil for MP4.
    public let pid: Int?
    /// Sampling frequency in Hz (the output rate, e.g. with SBR applied).
    public let samplingFrequency: Int?
    /// Number of audio channels, LFE included (5.1 is 6).
    public let channelCount: Int?
    /// Whether one of the channels is an LFE channel, when known.
    public let hasLFE: Bool?
    /// True for MPEG audio "dual channel" (two independent mono signals) or AC-3
    /// acmod 0 (1+1), which are two channels but not a stereo pair.
    public let isDualMono: Bool
    /// Bits per sample, when the container or header states it.
    public let bitsPerSample: Int?
    /// Maximum bit rate in bit/s, from `esds`/`btrt`, or the constant rate of
    /// AC-3 and LPCM.
    public let maximumBitRate: Int?
    /// Average bit rate in bit/s, from `esds`/`btrt`.
    public let averageBitRate: Int?
    /// The bit rate an MPEG audio or AC-3 frame header declares, in bit/s.
    public let frameBitRate: Int?
    /// The bit rates declared by the frame headers read in sequence, for MP3,
    /// whose PS3.5 8.2.5 / 8.2.12 rule is "CBR MPEG-1 LAYER III"; nil when the
    /// frames were not walked.
    public let bitRateScan: BitRateScan?
    /// The bit rate measured by walking every AAC frame of an MPEG-TS stream (ADTS or
    /// LATM/LOAS), which states none (D62); nil when the frames were not walked.
    public let measuredBitRate: MeasuredBitRate?

    /// The most bits an AAC stream carries in any one-second window of its
    /// presentation time, in bit/s — the measure an MP4 `esds` maxBitrate states
    /// ("maximum rate in bits/second over any window of one second", as FFmpeg's
    /// `movenc.c` writes it), measured here from the frames.
    ///
    /// ADTS frames give their length and sample count exactly (`aac_frame_length`,
    /// `number_of_raw_data_blocks_in_frame`), so the two bounds are equal and count
    /// the whole frame, header included (FFmpeg `adts_header.c` computes a frame's
    /// rate the same way). A LOAS AudioMuxElement is counted whole for the upper
    /// bound; the lower bound leaves out the most its useSameStreamMux bit,
    /// PayloadLengthInfo and byte alignment can take, and elements carrying a
    /// StreamMuxConfig entirely.
    public struct MeasuredBitRate: Sendable, Hashable {
        /// bit/s, counting only what is certainly audio payload.
        public let lowerBound: Int
        /// bit/s, counting the whole transport frames.
        public let upperBound: Int
        /// Frames measured.
        public let frameCount: Int
        /// True when every frame of the stream was measured; false when the walk
        /// stopped at ``AudioHeaderParser/maximumScannedFrames``, the read budget, a
        /// lost sync, or LATM elements that came before the first configuration.
        public let coversWholeStream: Bool

        public init(lowerBound: Int, upperBound: Int, frameCount: Int, coversWholeStream: Bool) {
            self.lowerBound = lowerBound
            self.upperBound = upperBound
            self.frameCount = frameCount
            self.coversWholeStream = coversWholeStream
        }
    }

    /// What a walk over consecutive MPEG audio frame headers found
    /// (ISO/IEC 11172-3 2.4.2.3, ISO/IEC 13818-3 2.4.2.3: every frame carries
    /// its own bitrate_index, so a stream is constant-rate exactly when all
    /// frames carry the same one).
    public struct BitRateScan: Sendable, Hashable {
        /// Frames whose headers were read, a leading Xing, Info or VBRI frame
        /// excluded.
        public let frameCount: Int
        /// The distinct bit rates those frames declare, in bit/s, ascending.
        public let bitRates: [Int]
        /// "Xing", "Info" or "VBRI" when the first frame is such an encoder
        /// header frame (a LAME/Xing tag or a Fraunhofer VBRI header; neither is
        /// part of ISO/IEC 11172-3, which sees an ordinary frame). "Xing" and
        /// "VBRI" are written for variable-rate streams, "Info" for constant-rate.
        public let encoderHeader: String?
        /// True when the walk reached the end of the stream; false when it stopped
        /// at the frame bound (``AudioHeaderParser/maximumScannedFrames``) or lost
        /// sync, so later frames were not read.
        public let coversWholeStream: Bool

        public init(frameCount: Int, bitRates: [Int], encoderHeader: String?, coversWholeStream: Bool) {
            self.frameCount = frameCount
            self.bitRates = bitRates
            self.encoderHeader = encoderHeader
            self.coversWholeStream = coversWholeStream
        }

        /// Whether the frames read are constant-rate: one bit rate, and no Xing or
        /// VBRI header declaring variable rate.
        public var isConstant: Bool {
            bitRates.count == 1 && encoderHeader != "Xing" && encoderHeader != "VBRI"
        }
    }

    public init(
        format: Format?,
        codecTag: String,
        pid: Int? = nil,
        samplingFrequency: Int? = nil,
        channelCount: Int? = nil,
        hasLFE: Bool? = nil,
        isDualMono: Bool = false,
        bitsPerSample: Int? = nil,
        maximumBitRate: Int? = nil,
        averageBitRate: Int? = nil,
        frameBitRate: Int? = nil,
        bitRateScan: BitRateScan? = nil,
        measuredBitRate: MeasuredBitRate? = nil
    ) {
        self.format = format
        self.codecTag = codecTag
        self.pid = pid
        self.samplingFrequency = samplingFrequency
        self.channelCount = channelCount
        self.hasLFE = hasLFE
        self.isDualMono = isDualMono
        self.bitsPerSample = bitsPerSample
        self.maximumBitRate = maximumBitRate
        self.averageBitRate = averageBitRate
        self.frameBitRate = frameBitRate
        self.bitRateScan = bitRateScan
        self.measuredBitRate = measuredBitRate
    }

    /// Formats whose coded stream carries no PCM sample depth: the bits per sample
    /// an encoder took in is not recoverable from AAC (ISO/IEC 13818-7, 14496-3),
    /// AC-3 / E-AC-3 (ETSI TS 102 366), MPEG audio (ISO/IEC 11172-3, 13818-3),
    /// DTS or Opus. An MP4 AudioSampleEntry's samplesize is then the ISO/IEC
    /// 14496-12 template value (16), not a measurement, so it is not kept.
    static let codedWithoutSampleDepth: Set<Format> = [
        .aac, .ac3, .eac3, .mp3, .mpeg1LayerII, .mpegLayerI, .dts, .opus,
    ]

    /// A track known only to exist — what ``VideoProbeResult`` holds when it is
    /// built from a bare `audioTrackCount`.
    public static let unidentified = VideoAudioTrack(format: nil, codecTag: "unknown")

    /// "AAC, 48 kHz, 2 channels, 16-bit, max 192 kbit/s" — the known fields only.
    public var summary: String {
        var parts: [String] = [format?.rawValue ?? "unidentified '\(codecTag)'"]
        if let rate = samplingFrequency { parts.append(Self.kilohertz(rate)) }
        if let count = channelCount {
            if count == 6, hasLFE == true {
                parts.append("5.1 channels")
            } else if isDualMono {
                parts.append("2 channels (dual mono)")
            } else {
                parts.append("\(count) channel\(count == 1 ? "" : "s")")
            }
        }
        if let bits = bitsPerSample { parts.append("\(bits)-bit") }
        if let rate = maximumBitRate {
            parts.append("max \(Self.kilobits(rate))")
        } else if let rate = frameBitRate {
            parts.append(Self.kilobits(rate))
        } else if let rate = averageBitRate {
            parts.append("avg \(Self.kilobits(rate))")
        }
        return parts.joined(separator: ", ")
    }

    /// "44.1 kHz", "48 kHz".
    static func kilohertz(_ hertz: Int) -> String {
        hertz % 1000 == 0 ? "\(hertz / 1000) kHz" : "\(Double(hertz) / 1000) kHz"
    }

    /// "640 kbit/s", "4608 kbit/s".
    static func kilobits(_ bitsPerSecond: Int) -> String {
        bitsPerSecond % 1000 == 0
            ? "\(bitsPerSecond / 1000) kbit/s"
            : "\(Double(bitsPerSecond) / 1000) kbit/s"
    }
}

// MARK: - Constraints

/// What one audio format must satisfy under a video transfer syntax, as PS3.5
/// 2026a states it.
///
/// Reference: PS3.5 8.2.5 (MPEG2; 8.2.6 applies it to MP@HL), 8.2.12 and
/// Table 8.2.12-1 (H.264 and HEVC, 8.2.7-8.2.11).
public struct VideoAudioConstraint: Sendable, Hashable {
    /// The format the constraint applies to.
    public let format: VideoAudioTrack.Format
    /// The section stating it: "PS3.5 8.2.5" or "PS3.5 8.2.12".
    public let section: String
    /// Maximum bit rate in bit/s, or nil where none is stated (8.2.5).
    public let maximumBitRate: Int?
    /// Permitted sampling frequencies in Hz (for MP3, of the main channel).
    public let samplingFrequencies: [Int]
    /// Exact permitted bits per sample, when the standard lists values.
    public let permittedBitsPerSample: [Int]?
    /// Upper bound on bits per sample, when the standard says "up to".
    public let maximumBitsPerSample: Int?
    /// Permitted channel counts (5.1 is 6), or nil for MP3's "one main mono or
    /// stereo channel, and optionally one or more complementary channel(s)",
    /// which a channel count cannot violate.
    public let permittedChannelCounts: [Int]?
    /// The standard's wording for the channel rule.
    public let channelsText: String
    /// The standard's wording for the bits-per-sample rule.
    public let bitsPerSampleText: String
    /// Whether the format may be carried in an MP4 container.
    public let permittedInMP4: Bool
    /// Whether the format may be carried in an MPEG-2 Transport Stream.
    public let permittedInMPEG2TS: Bool
    /// Whether the standard requires constant bit rate ("CBR MPEG-1 LAYER III").
    public let requiresConstantBitRate: Bool
}

// MARK: - Violations

/// One way an audio track breaks PS3.5 8.2.5 or 8.2.12.
public struct VideoAudioViolation: Sendable, Hashable {

    /// The constraint concerned. Also used to list what could not be checked.
    public enum Constraint: String, Sendable, Hashable, CaseIterable {
        case format = "audio format"
        case container = "container"
        case maximumBitRate = "maximum bit rate"
        case samplingFrequency = "sampling frequency"
        case bitsPerSample = "bits per sample"
        case channels = "number of channels"
        case constantBitRate = "constant bit rate"
        /// MP3's "optionally one or more complementary channel(s)" (PS3.5 8.2.5,
        /// 8.2.12): the ISO/IEC 13818-3 multichannel extension.
        case complementaryChannels = "complementary channels"
    }

    /// Which constraint is violated.
    public let constraint: Constraint
    /// A sentence naming the observed value and what the standard allows.
    public let message: String

    public init(constraint: Constraint, message: String) {
        self.constraint = constraint
        self.message = message
    }
}

/// Why one constraint is not, or cannot be, judged from the bit stream.
public struct VideoAudioCheckNote: Sendable, Hashable {
    /// The constraint concerned.
    public let constraint: VideoAudioViolation.Constraint
    /// A sentence giving the reason.
    public let message: String

    public init(constraint: VideoAudioViolation.Constraint, message: String) {
        self.constraint = constraint
        self.message = message
    }
}

/// The PS3.5 8.2.5 / 8.2.12 check of one audio track.
public struct VideoAudioTrackCheck: Sendable, Hashable {
    /// 1-based position among the input's audio tracks.
    public let trackNumber: Int
    /// The track checked.
    public let track: VideoAudioTrack
    /// Constraints the track is known to break.
    public let violations: [VideoAudioViolation]
    /// Constraints that could not be checked because the value is unknown.
    public let notChecked: [VideoAudioViolation.Constraint]
    /// Explanations: a constraint the coded format cannot show at all (bits per
    /// sample of compressed audio, neither a violation nor "not checked"), and
    /// why an entry of ``notChecked`` stays there.
    public let notes: [VideoAudioCheckNote]

    public init(
        trackNumber: Int,
        track: VideoAudioTrack,
        violations: [VideoAudioViolation],
        notChecked: [VideoAudioViolation.Constraint],
        notes: [VideoAudioCheckNote] = []
    ) {
        self.trackNumber = trackNumber
        self.track = track
        self.violations = violations
        self.notChecked = notChecked
        self.notes = notes
    }
}

/// The outcome of checking every audio track against a video transfer syntax.
public struct VideoAudioConformanceResult: Sendable, Hashable {
    /// The section applied: "PS3.5 8.2.5" (MPEG2) or "PS3.5 8.2.12".
    public let section: String
    /// One entry per audio track, in container order.
    public let tracks: [VideoAudioTrackCheck]

    public init(section: String, tracks: [VideoAudioTrackCheck]) {
        self.section = section
        self.tracks = tracks
    }

    /// Every known violation, in track order.
    public var violations: [VideoAudioViolation] { tracks.flatMap(\.violations) }

    /// True when no track is known to violate the constraints. Constraints that
    /// could not be checked do not count against it.
    public var hasNoKnownViolations: Bool { violations.isEmpty }
}

// MARK: - Checking

extension VideoConformanceValidator {

    /// The audio constraints a video transfer syntax imposes, extracted from PS3.5
    /// 2026a; empty for a transfer syntax that is not a video one.
    ///
    /// MPEG2 (8.2.5, applied to MP@HL by 8.2.6): "CBR MPEG-1 LAYER III (MP3)
    /// Audio Standard", "up to 24 bits", "32 kHz, 44.1 kHz or 48 kHz for the main
    /// channel", "one main mono or stereo channel, and optionally one or more
    /// complementary channel(s)"; no bit rate or container limit.
    ///
    /// H.264 and HEVC (8.2.12, Table 8.2.12-1):
    ///
    /// | Format | Max bit rate | Sampling | Bits | Channels | Container |
    /// |---|---|---|---|---|---|
    /// | LPCM | 4.608 Mbps | 48, 96 kHz | 16, 20, 24 | 2 | MPEG-2 TS |
    /// | AC-3 | 640 kbps | 48 kHz | 16 | 2 or 5.1 | MPEG-2 TS |
    /// | AAC | 640 kbps | 48 kHz | 16, 20, 24 | 2 or 5.1 | TS or MP4 |
    /// | MP3 (CBR) | 320 kbps | 32, 44.1, 48 kHz (main) | up to 24 | main mono/stereo + complementary | TS or MP4 |
    /// | MPEG-1 Layer II | 384 kbps | 32, 44.1, 48 kHz | up to 24 | 2 | TS or MP4 |
    public static func audioConstraints(for transferSyntax: TransferSyntax) -> [VideoAudioConstraint] {
        guard let video = constraints(for: transferSyntax) else { return [] }
        let mp3Channels = "one main mono or stereo channel, and optionally one or more "
            + "complementary channel(s)"
        if video.codec == .mpeg2 {
            return [VideoAudioConstraint(
                format: .mp3, section: "PS3.5 8.2.5",
                maximumBitRate: nil,
                samplingFrequencies: [32000, 44100, 48000],
                permittedBitsPerSample: nil, maximumBitsPerSample: 24,
                permittedChannelCounts: nil, channelsText: mp3Channels,
                bitsPerSampleText: "up to 24 bits",
                permittedInMP4: true, permittedInMPEG2TS: true,
                requiresConstantBitRate: true)]
        }
        let section = "PS3.5 8.2.12"
        return [
            VideoAudioConstraint(
                format: .lpcm, section: section,
                maximumBitRate: 4_608_000, samplingFrequencies: [48000, 96000],
                permittedBitsPerSample: [16, 20, 24], maximumBitsPerSample: nil,
                permittedChannelCounts: [2], channelsText: "2 channels",
                bitsPerSampleText: "16, 20 or 24 bits",
                permittedInMP4: false, permittedInMPEG2TS: true,
                requiresConstantBitRate: false),
            VideoAudioConstraint(
                format: .ac3, section: section,
                maximumBitRate: 640_000, samplingFrequencies: [48000],
                permittedBitsPerSample: [16], maximumBitsPerSample: nil,
                permittedChannelCounts: [2, 6], channelsText: "2 or 5.1 channels",
                bitsPerSampleText: "16 bits",
                permittedInMP4: false, permittedInMPEG2TS: true,
                requiresConstantBitRate: false),
            VideoAudioConstraint(
                format: .aac, section: section,
                maximumBitRate: 640_000, samplingFrequencies: [48000],
                permittedBitsPerSample: [16, 20, 24], maximumBitsPerSample: nil,
                permittedChannelCounts: [2, 6], channelsText: "2 or 5.1 channels",
                bitsPerSampleText: "16, 20 or 24 bits",
                permittedInMP4: true, permittedInMPEG2TS: true,
                requiresConstantBitRate: false),
            VideoAudioConstraint(
                format: .mp3, section: section,
                maximumBitRate: 320_000, samplingFrequencies: [32000, 44100, 48000],
                permittedBitsPerSample: nil, maximumBitsPerSample: 24,
                permittedChannelCounts: nil, channelsText: mp3Channels,
                bitsPerSampleText: "up to 24 bits",
                permittedInMP4: true, permittedInMPEG2TS: true,
                requiresConstantBitRate: true),
            VideoAudioConstraint(
                format: .mpeg1LayerII, section: section,
                maximumBitRate: 384_000, samplingFrequencies: [32000, 44100, 48000],
                permittedBitsPerSample: nil, maximumBitsPerSample: 24,
                permittedChannelCounts: [2], channelsText: "2 channels",
                bitsPerSampleText: "up to 24 bits",
                permittedInMP4: true, permittedInMPEG2TS: true,
                requiresConstantBitRate: false),
        ]
    }

    /// Checks audio tracks against the audio constraints of a video transfer
    /// syntax (PS3.5 8.2.5 for MPEG2, 8.2.12 for H.264 and HEVC).
    ///
    /// A value the container does not expose is listed in
    /// ``VideoAudioTrackCheck/notChecked``, never reported as a violation.
    ///
    /// - Parameters:
    ///   - tracks: The audio tracks, as ``VideoProbe`` found them.
    ///   - container: The container carrying them, which Table 8.2.12-1 constrains
    ///     for LPCM and AC-3.
    ///   - transferSyntax: The transfer syntax the object declares.
    public static func validateAudio(
        tracks: [VideoAudioTrack],
        container: VideoContainer,
        transferSyntax: TransferSyntax
    ) -> VideoAudioConformanceResult {
        let table = audioConstraints(for: transferSyntax)
        let section = table.first?.section ?? "PS3.5 8.2.12"
        let checks = tracks.enumerated().map { index, track in
            check(track, number: index + 1, table: table, section: section, container: container)
        }
        return VideoAudioConformanceResult(section: section, tracks: checks)
    }

    private static func check(
        _ track: VideoAudioTrack,
        number: Int,
        table: [VideoAudioConstraint],
        section: String,
        container: VideoContainer
    ) -> VideoAudioTrackCheck {
        typealias C = VideoAudioViolation.Constraint
        guard let format = track.format else {
            return VideoAudioTrackCheck(
                trackNumber: number, track: track, violations: [], notChecked: C.allCases)
        }
        guard let rule = table.first(where: { $0.format == Self.constraintFormat(for: format) }) else {
            let permitted = table.map(\.format.rawValue)
            let allowed = permitted.count == 1
                ? "only CBR MPEG-1 Layer III (MP3)"
                : permitted.dropLast().joined(separator: ", ") + " or " + (permitted.last ?? "")
            return VideoAudioTrackCheck(
                trackNumber: number, track: track,
                violations: [VideoAudioViolation(
                    constraint: .format,
                    message: "\(format.rawValue) is not a permitted audio format; "
                        + "\(section) allows \(allowed)")],
                notChecked: [])
        }

        var violations: [VideoAudioViolation] = []
        var notChecked: [C] = []
        var notes: [VideoAudioCheckNote] = []
        let name = format.rawValue

        // Container (Table 8.2.12-1).
        switch container {
        case .mpegTS:
            if !rule.permittedInMPEG2TS {
                violations.append(VideoAudioViolation(
                    constraint: .container,
                    message: "\(name) is not permitted in an MPEG-2 TS container (\(section))"))
            }
        case .mp4, .quickTime:
            if !rule.permittedInMP4 {
                violations.append(VideoAudioViolation(
                    constraint: .container,
                    message: "\(name) is permitted only in an MPEG-2 TS container, "
                        + "not \(container.displayName) (PS3.5 Table 8.2.12-1)"))
            }
        case .mpegPS, .mpegPES, .elementaryStream, .unknown:
            notChecked.append(.container)
        }

        // Maximum bit rate.
        if let limit = rule.maximumBitRate {
            let observed = [track.maximumBitRate, track.averageBitRate, track.frameBitRate]
                .compactMap { $0 }.max()
            let measured = track.measuredBitRate
            if let observed, observed > limit {
                violations.append(VideoAudioViolation(
                    constraint: .maximumBitRate,
                    message: "bit rate \(VideoAudioTrack.kilobits(observed)) exceeds the "
                        + "\(section) maximum of \(VideoAudioTrack.kilobits(limit)) for \(name)"))
            } else if let measured, measured.lowerBound > limit {
                // Even what is certainly payload exceeds the limit in some second (D62).
                violations.append(VideoAudioViolation(
                    constraint: .maximumBitRate,
                    message: "bit rate \(VideoAudioTrack.kilobits(measured.lowerBound)) (the most "
                        + "carried in any one second of the \(measured.frameCount) frames read) exceeds "
                        + "the \(section) maximum of \(VideoAudioTrack.kilobits(limit)) for \(name)"))
            } else if let measured, measured.coversWholeStream, measured.upperBound <= limit {
                // Every frame measured, and even the whole transport frames fit (D62).
            } else if track.maximumBitRate == nil
                        && !(track.frameBitRate != nil && Self.frameRateBoundsStream(format)) {
                // An average within the limit says nothing about the peak.
                notChecked.append(.maximumBitRate)
                if let measured {
                    let reason = measured.coversWholeStream
                        ? "the transport overhead leaves it between "
                            + "\(VideoAudioTrack.kilobits(measured.lowerBound)) and "
                            + "\(VideoAudioTrack.kilobits(measured.upperBound))"
                        : "only \(measured.frameCount) frames were measured (at most "
                            + "\(VideoAudioTrack.kilobits(measured.upperBound)) in any second of them)"
                    notes.append(VideoAudioCheckNote(
                        constraint: .maximumBitRate,
                        message: "maximum bit rate not established: \(reason)"))
                }
            }
        }

        // Sampling frequency.
        if let rate = track.samplingFrequency {
            if !rule.samplingFrequencies.contains(rate) {
                let allowed = rule.samplingFrequencies.map(VideoAudioTrack.kilohertz)
                let list = allowed.count == 1
                    ? allowed[0]
                    : allowed.dropLast().joined(separator: ", ") + " or " + (allowed.last ?? "")
                let qualifier = rule.permittedChannelCounts == nil ? " for the main channel" : ""
                violations.append(VideoAudioViolation(
                    constraint: .samplingFrequency,
                    message: "sampling frequency \(VideoAudioTrack.kilohertz(rate)) is not "
                        + "permitted for \(name); \(section) allows \(list)\(qualifier)"))
            }
        } else {
            notChecked.append(.samplingFrequency)
        }

        // Bits per sample.
        if let bits = track.bitsPerSample {
            let permitted = rule.permittedBitsPerSample.map { $0.contains(bits) }
                ?? rule.maximumBitsPerSample.map { bits <= $0 } ?? true
            if !permitted {
                violations.append(VideoAudioViolation(
                    constraint: .bitsPerSample,
                    message: "\(bits) bits per sample is not permitted for \(name); "
                        + "\(section) allows \(rule.bitsPerSampleText)"))
            }
        } else if VideoAudioTrack.codedWithoutSampleDepth.contains(format) {
            // Table 8.2.12-1 states a bits-per-sample value for compressed formats
            // too, but their coded streams carry no PCM sample depth, so the
            // value cannot be read from any bit stream: not a violation, and not
            // "not checked" either, since no further reading would find it.
            notes.append(VideoAudioCheckNote(
                constraint: .bitsPerSample,
                message: "bits per sample (\(rule.bitsPerSampleText)) cannot be read from the "
                    + "bit stream: \(name) is coded without a PCM sample depth "
                    + "(\(Self.codingSpecification(format)))"))
        } else {
            notChecked.append(.bitsPerSample)
        }

        // Number of channels.
        if let counts = rule.permittedChannelCounts {
            if let count = track.channelCount {
                // 5.1 is six channels, one of them LFE; six without LFE is not 5.1.
                let isFivePointOne = count == 6 && track.hasLFE != false
                let permitted = counts.contains(count) && (count != 6 || isFivePointOne)
                if !permitted {
                    let observed = count == 6 ? "6 channels without LFE"
                        : "\(count) channel\(count == 1 ? "" : "s")"
                    violations.append(VideoAudioViolation(
                        constraint: .channels,
                        message: "\(observed) is not permitted for \(name); "
                            + "\(section) allows \(rule.channelsText)"))
                }
            } else {
                notChecked.append(.channels)
            }
        }

        // MP3's main channel is "one main mono or stereo channel" (PS3.5 8.2.5,
        // 8.2.12), in the terms of the MPEG-1 Part 3 those sections name: its mode is
        // single_channel (mono) or stereo / joint_stereo. dual_channel — two
        // independent mono programmes — is a mode of its own, neither mono nor a
        // stereo pair, so it is not permitted (D61; the (003A,0300) Items refuse it
        // for the same reason).
        if rule.permittedChannelCounts == nil, track.isDualMono {
            violations.append(VideoAudioViolation(
                constraint: .channels,
                message: "dual channel mode (two independent mono programmes, ISO/IEC 11172-3) "
                    + "is neither a mono nor a stereo main channel; \(section) allows "
                    + "\(rule.channelsText) for \(name)"))
        }

        // MP3's complementary channels: the multichannel extension of ISO/IEC
        // 13818-3 is carried in the ancillary data of each MPEG-1 compatible
        // frame (after the Layer III main data, located only by decoding the side
        // information and the bit reservoir), or in a separate extension stream
        // the base frames do not point to. Nothing in the frame header marks it,
        // so it is not identified.
        if rule.permittedChannelCounts == nil {
            notChecked.append(.complementaryChannels)
            notes.append(VideoAudioCheckNote(
                constraint: .complementaryChannels,
                message: "complementary channels are not identified: the ISO/IEC 13818-3 "
                    + "multichannel extension has no frame-header flag and sits in the "
                    + "Layer III ancillary data or a separate extension stream"))
        }

        // Constant bit rate (8.2.5, 8.2.12 "CBR MPEG-1 LAYER III"): every frame
        // header carries its own bitrate_index, walked by the probe.
        if rule.requiresConstantBitRate {
            if let scan = track.bitRateScan,
               scan.frameCount > 0 || (scan.encoderHeader != nil && scan.encoderHeader != "Info") {
                if !scan.isConstant {
                    let evidence: String
                    if let header = scan.encoderHeader, header != "Info" {
                        evidence = "its first frame is a \(header) header, which encoders write "
                            + "for variable bit rate"
                    } else {
                        let rates = scan.bitRates.map(VideoAudioTrack.kilobits)
                        evidence = "its frames declare \(rates.joined(separator: ", ")) "
                            + "(\(scan.frameCount) frames read)"
                    }
                    violations.append(VideoAudioViolation(
                        constraint: .constantBitRate,
                        message: "\(name) is not constant bit rate: \(evidence); "
                            + "\(section) requires CBR MPEG-1 Layer III"))
                }
            } else {
                notChecked.append(.constantBitRate)
            }
        }

        return VideoAudioTrackCheck(
            trackNumber: number, track: track, violations: violations,
            notChecked: notChecked, notes: notes)
    }

    /// The Table 8.2.12-1 row a format is judged by.
    ///
    /// E-AC-3 is judged by the AC-3 row (D59). PS3.5 2026a 8.2.12: "AC-3 is
    /// standardized in [ETSI TS 102 366]", and the PS3.5 2026a bibliography entry
    /// for that reference reads "ETSI TS 102 366 ETSI Feb. 2005 Audio Compression
    /// (AC-3, Enhanced AC-3) Standard". The whole specification is cited, Enhanced
    /// AC-3 (its Annex E) included, and nothing in 8.2.12 excludes it, so E-AC-3
    /// is permitted when it meets the same limits: "Maximum bit rate: 640kbps
    /// Sampling frequency: 48kHz Bits per sample: 16 bits Number of channels: 2
    /// or 5.1 channels" and "If AC-3 is used for Audio components, the container
    /// format shall be MPEG-2 TS." Violations of those limits are reported under
    /// the E-AC-3 name. 8.2.5 (MPEG2) permits only MP3, so there E-AC-3 still
    /// fails the format check.
    static func constraintFormat(for format: VideoAudioTrack.Format) -> VideoAudioTrack.Format {
        format == .eac3 ? .ac3 : format
    }

    /// The specification that codes a compressed format (outside DICOM).
    static func codingSpecification(_ format: VideoAudioTrack.Format) -> String {
        switch format {
        case .aac: return "ISO/IEC 13818-7, ISO/IEC 14496-3"
        case .ac3, .eac3: return "ETSI TS 102 366"
        case .mp3, .mpeg1LayerII, .mpegLayerI: return "ISO/IEC 11172-3, ISO/IEC 13818-3"
        default: return format.rawValue
        }
    }

    /// Whether one frame header's bit rate bounds the whole stream: AC-3 is coded
    /// at a constant rate (ETSI TS 102 366 frmsizecod), LPCM's rate follows from
    /// its format, and no MPEG-1/2 Layer II or III bit rate index exceeds the
    /// PS3.5 limits (384 and 320 kbit/s), so any non-free-format frame is within.
    /// E-AC-3 is not listed: its frame size (frmsiz) may vary from frame to frame.
    private static func frameRateBoundsStream(_ format: VideoAudioTrack.Format) -> Bool {
        format == .ac3 || format == .lpcm || format == .mp3 || format == .mpeg1LayerII
    }
}

// MARK: - Multiplexed Audio Channels Description

extension VideoAudioChannel {

    /// The Items of Multiplexed Audio Channels Description Code Sequence
    /// (003A,0300) for a set of audio tracks, or nil when they cannot be described
    /// honestly.
    ///
    /// PS3.3 2026a Table C.7-13 gives each Item a Channel Identification Code
    /// (003A,0301) — "1 for the main channel, 2 for the second channel and 3 to 9
    /// to the complementary channels" —, a Channel Mode (003A,0302) whose
    /// Enumerated Values are MONO ("1 signal") and STEREO ("2 simultaneously
    /// acquired (left and right) signals"), and a Channel Source Sequence
    /// (003A,0208) holding one code, "DCID 3000" (PS3.16 CID 3000 Audio Channel
    /// Source, Extensible, so any code may be given).
    ///
    /// Each audio track is one channel in that sense, numbered in container order.
    /// The mode follows from the track's channel count. The source cannot be read
    /// from any container, so the caller supplies it. Returns nil when a track's
    /// channel count is unknown, is not 1 or 2 (5.1 has no Channel Mode), is dual
    /// mono (two signals that are not a left/right pair), or when there are more
    /// than nine tracks.
    public static func channels(
        describing tracks: [VideoAudioTrack],
        source: Source
    ) -> [VideoAudioChannel]? {
        channels(describing: tracks, sources: Array(repeating: source, count: tracks.count))
    }

    /// The (003A,0300) Items with one Channel Source per track, in container order
    /// (P-AUDIO-SOURCE-PER-TRACK): PS3.3 2026a Table C.7-13 gives every Item its own
    /// Channel Source Sequence (003A,0208). Nil when `sources` does not hold exactly
    /// one source per track, or for the reasons of ``channels(describing:source:)``.
    public static func channels(
        describing tracks: [VideoAudioTrack],
        sources: [Source]
    ) -> [VideoAudioChannel]? {
        guard !tracks.isEmpty, tracks.count <= 9, sources.count == tracks.count else { return nil }
        var channels: [VideoAudioChannel] = []
        for (index, track) in tracks.enumerated() {
            guard !track.isDualMono, let count = track.channelCount else { return nil }
            let mode: Mode
            switch count {
            case 1: mode = .mono
            case 2: mode = .stereo
            default: return nil
            }
            channels.append(VideoAudioChannel(
                channelIdentificationCode: index + 1, mode: mode, source: sources[index]))
        }
        return channels
    }
}

// MARK: - Header Parsing

/// Reads the few header fields the audio check needs from the first frame or the
/// decoder configuration of an audio track. Plain byte handling, no decoding.
enum AudioHeaderParser {

    // MARK: MPEG audio (ISO/IEC 11172-3 2.4.1.3, ISO/IEC 13818-3 2.4.1.3)

    /// A parsed MPEG audio frame header.
    struct MPEGAudioHeader: Equatable {
        /// 1, 2 or 3.
        let layer: Int
        /// 1 for MPEG-1, 2 for MPEG-2 LSF, 25 for MPEG-2.5.
        let version: Int
        let samplingFrequency: Int
        /// nil for free format.
        let bitRate: Int?
        /// 3 = single channel (mono); 2 = dual channel.
        let mode: Int
        /// bitrate_index, 0 (free format) to 14.
        var bitRateIndex: Int = 0
        /// padding_bit.
        var padding: Int = 0
        /// True when protection_bit is 0, so a 16-bit CRC follows the header.
        var hasCRC: Bool = false

        /// The frame length in bytes (ISO/IEC 11172-3 2.4.3.1, ISO/IEC 13818-3
        /// 2.4.3.1: Layer I slots are 4 bytes, and MPEG-2 LSF Layer III frames hold
        /// 576 samples); nil in free format, whose length the header does not give.
        var frameLength: Int? {
            guard let rate = bitRate else { return nil }
            switch layer {
            case 1: return (12 * rate / samplingFrequency + padding) * 4
            case 3 where version != 1: return 72 * rate / samplingFrequency + padding
            default: return 144 * rate / samplingFrequency + padding
            }
        }

        /// Where a Layer III frame's main data starts: after the header, the CRC
        /// and the side information (ISO/IEC 11172-3 2.4.1.7; 13818-3 halves it
        /// for LSF). An encoder header ("Xing"/"Info") is written there.
        var sideInfoEnd: Int {
            let sideInfo = version == 1 ? (mode == 3 ? 17 : 32) : (mode == 3 ? 9 : 17)
            return 4 + (hasCRC ? 2 : 0) + sideInfo
        }

        var channelCount: Int { mode == 3 ? 1 : 2 }
        var format: VideoAudioTrack.Format {
            switch layer {
            case 3: return .mp3
            case 2: return .mpeg1LayerII
            default: return .mpegLayerI
            }
        }

        func track(codecTag: String, pid: Int? = nil) -> VideoAudioTrack {
            VideoAudioTrack(
                format: format, codecTag: codecTag, pid: pid,
                samplingFrequency: samplingFrequency, channelCount: channelCount,
                hasLFE: false, isDualMono: mode == 2, frameBitRate: bitRate)
        }
    }

    private static let mpeg1BitRates: [[Int]] = [
        [0, 32, 64, 96, 128, 160, 192, 224, 256, 288, 320, 352, 384, 416, 448],  // Layer I
        [0, 32, 48, 56, 64, 80, 96, 112, 128, 160, 192, 224, 256, 320, 384],     // Layer II
        [0, 32, 40, 48, 56, 64, 80, 96, 112, 128, 160, 192, 224, 256, 320],      // Layer III
    ]
    private static let mpeg2BitRates: [[Int]] = [
        [0, 32, 48, 56, 64, 80, 96, 112, 128, 144, 160, 176, 192, 224, 256],     // Layer I
        [0, 8, 16, 24, 32, 40, 48, 56, 64, 80, 96, 112, 128, 144, 160],          // Layer II
        [0, 8, 16, 24, 32, 40, 48, 56, 64, 80, 96, 112, 128, 144, 160],          // Layer III
    ]

    /// Parses a 4-byte MPEG audio header at `offset`.
    static func mpegAudioHeader(_ bytes: [UInt8], at offset: Int = 0) -> MPEGAudioHeader? {
        guard offset + 4 <= bytes.count else { return nil }
        let b1 = bytes[offset + 1], b2 = bytes[offset + 2], b3 = bytes[offset + 3]
        guard bytes[offset] == 0xFF, b1 & 0xE0 == 0xE0 else { return nil }
        let versionBits = (b1 >> 3) & 0x03   // 00 2.5, 01 reserved, 10 MPEG-2, 11 MPEG-1
        let layerBits = (b1 >> 1) & 0x03     // 01 III, 10 II, 11 I
        guard versionBits != 1, layerBits != 0 else { return nil }
        let bitRateIndex = Int(b2 >> 4)
        let rateIndex = Int((b2 >> 2) & 0x03)
        guard bitRateIndex != 15, rateIndex != 3 else { return nil }
        let layer = 4 - Int(layerBits)
        let base = [44100, 48000, 32000][rateIndex]
        let version: Int
        let rate: Int
        switch versionBits {
        case 3: version = 1; rate = base
        case 2: version = 2; rate = base / 2
        default: version = 25; rate = base / 4
        }
        let table = version == 1 ? mpeg1BitRates : mpeg2BitRates
        let kbps = table[layer - 1][bitRateIndex]
        return MPEGAudioHeader(
            layer: layer, version: version, samplingFrequency: rate,
            bitRate: kbps == 0 ? nil : kbps * 1000, mode: Int(b3 >> 6),
            bitRateIndex: bitRateIndex, padding: Int((b2 >> 1) & 0x01),
            hasCRC: b1 & 0x01 == 0)
    }

    /// The first MPEG audio header in a window, confirmed by a second header at
    /// the next frame when the frame length can be computed.
    static func findMPEGAudioHeader(_ bytes: [UInt8], limit: Int = 4096) -> MPEGAudioHeader? {
        findMPEGAudioFrame(bytes, limit: limit)?.header
    }

    /// The first confirmed MPEG audio header in a window, with its offset.
    static func findMPEGAudioFrame(
        _ bytes: [UInt8], limit: Int = 4096
    ) -> (header: MPEGAudioHeader, offset: Int)? {
        let end = min(bytes.count - 4, limit)
        guard end >= 0 else { return nil }
        for offset in 0...end {
            guard let header = mpegAudioHeader(bytes, at: offset) else { continue }
            // Confirm with the next header where one fits in the window.
            if let length = header.frameLength {
                let next = offset + length
                if next + 4 <= bytes.count {
                    guard let second = mpegAudioHeader(bytes, at: next),
                          second.layer == header.layer,
                          second.samplingFrequency == header.samplingFrequency
                    else { continue }
                }
            }
            return (header, offset)
        }
        return nil
    }

    // MARK: MPEG audio bit rate walk (CBR, PS3.5 8.2.5 / 8.2.12)

    /// The most frame headers one walk reads. 2,000 Layer III frames are about
    /// 42 s at 48 kHz (1,152 samples each); a stream that changes rate only after
    /// that is reported as constant for the part read
    /// (``VideoAudioTrack/BitRateScan/coversWholeStream`` is then false). The bound
    /// keeps a long file from being walked in full on every probe.
    static let maximumScannedFrames = 2000

    /// The encoder header a first Layer III frame carries, if any: "Xing" or
    /// "Info" at the end of the side information (LAME/Xing), or "VBRI" 32 bytes
    /// after the header (Fraunhofer). Both are frames an ISO/IEC 11172-3 decoder
    /// plays as silence; the tags are de facto, not ISO.
    static func encoderHeader(_ bytes: ArraySlice<UInt8>, header: MPEGAudioHeader) -> String? {
        func tag(at offset: Int) -> String? {
            let start = bytes.startIndex + offset
            guard offset >= 0, start + 4 <= bytes.endIndex else { return nil }
            return String(bytes: bytes[start..<(start + 4)], encoding: .ascii)
        }
        guard header.layer == 3 else { return nil }
        if let found = tag(at: header.sideInfoEnd), found == "Xing" || found == "Info" { return found }
        if tag(at: 36) == "VBRI" { return "VBRI" }
        return nil
    }

    /// Folds a sequence of frame headers into a ``VideoAudioTrack/BitRateScan``.
    ///
    /// - Parameters:
    ///   - frames: Each frame's header and bytes from its start (enough to hold an
    ///     encoder header for the first), in stream order.
    ///   - coversWholeStream: Whether `frames` reaches the end of the stream.
    /// - Returns: nil when no frame was read, or one is free format (bitrate_index
    ///   0), whose rate the header does not state.
    static func bitRateScan(
        _ frames: [(header: MPEGAudioHeader, bytes: ArraySlice<UInt8>)],
        coversWholeStream: Bool
    ) -> VideoAudioTrack.BitRateScan? {
        guard let first = frames.first else { return nil }
        let encoder = encoderHeader(first.bytes, header: first.header)
        let counted = encoder == nil ? frames[...] : frames.dropFirst()
        var rates: Set<Int> = []
        for frame in counted {
            guard let rate = frame.header.bitRate else { return nil }
            rates.insert(rate)
        }
        guard !counted.isEmpty || encoder != nil else { return nil }
        return VideoAudioTrack.BitRateScan(
            frameCount: counted.count, bitRates: rates.sorted(),
            encoderHeader: encoder, coversWholeStream: coversWholeStream)
    }

    /// Walks consecutive MPEG audio frames of an elementary stream (for MPEG-TS,
    /// the PES payloads of one PID) from its first confirmed header, each header
    /// giving the next frame's offset, up to ``maximumScannedFrames``.
    static func scanMPEGAudioFrames(_ bytes: [UInt8]) -> VideoAudioTrack.BitRateScan? {
        guard let start = findMPEGAudioFrame(bytes) else { return nil }
        var frames: [(header: MPEGAudioHeader, bytes: ArraySlice<UInt8>)] = []
        var offset = start.offset
        var reachedEnd = false
        while frames.count < maximumScannedFrames {
            guard let header = mpegAudioHeader(bytes, at: offset),
                  header.layer == start.header.layer,
                  header.samplingFrequency == start.header.samplingFrequency,
                  let length = header.frameLength
            else {
                // Fewer than four bytes left is the end of the stream; anything
                // else is lost sync, and the walk stops at what it has read.
                reachedEnd = offset + 4 > bytes.count
                break
            }
            frames.append((header, bytes[offset..<min(offset + length, bytes.count)]))
            offset += length
            if offset >= bytes.count { reachedEnd = true; break }
        }
        return bitRateScan(frames, coversWholeStream: reachedEnd)
    }

    // MARK: AAC (ISO/IEC 13818-7 ADTS; ISO/IEC 14496-3 1.6.2.1 AudioSpecificConfig)

    static let aacSamplingFrequencies = [
        96000, 88200, 64000, 48000, 44100, 32000, 24000, 22050, 16000, 12000, 11025, 8000, 7350,
    ]

    /// Channel count for channelConfiguration 1-7 (ISO/IEC 14496-3 Table 1.19).
    static func aacChannels(_ configuration: Int) -> (count: Int, lfe: Bool)? {
        switch configuration {
        case 1: return (1, false)
        case 2: return (2, false)
        case 3: return (3, false)
        case 4: return (4, false)
        case 5: return (5, false)
        case 6: return (6, true)
        case 7: return (8, true)
        default: return nil
        }
    }

    /// Audio Object Types built on the General Audio (AAC) coder of ISO/IEC
    /// 14496-3 Subpart 4, which PS3.5 8.2.12 names; SBR (5) and PS (29) extend it.
    static let aacObjectTypes: Set<Int> = [1, 2, 3, 4, 5, 6, 17, 19, 20, 22, 23, 29, 39]

    /// A parsed AudioSpecificConfig.
    struct AudioSpecificConfig: Equatable {
        let audioObjectType: Int
        let samplingFrequency: Int?
        let channelConfiguration: Int
        /// The core coder's sampling frequency (before SBR), which times its frames.
        var coreSamplingFrequency: Int? = nil
        /// Samples per core frame from GASpecificConfig's frameLengthFlag: 1024 or 960
        /// for object types 1–4 and 17, 512 or 480 for 23 and 39 (the layout FFmpeg's
        /// `mpeg4audio.c` reads); nil for other object types.
        var frameLength: Int? = nil

        var format: VideoAudioTrack.Format {
            if AudioHeaderParser.aacObjectTypes.contains(audioObjectType) { return .aac }
            switch audioObjectType {
            case 32: return .mpegLayerI
            case 33: return .mpeg1LayerII
            case 34: return .mp3
            default: return VideoAudioTrack.Format(rawValue: "MPEG-4 Audio object type \(audioObjectType)")
            }
        }
    }

    static func audioSpecificConfig(_ data: Data) -> AudioSpecificConfig? {
        var reader = BitstreamReader(data)
        return audioSpecificConfig(&reader)
    }

    /// Reads an AudioSpecificConfig at the reader's position, which need not be
    /// byte-aligned (in LATM it follows StreamMuxConfig's bit fields).
    static func audioSpecificConfig(_ reader: inout BitstreamReader) -> AudioSpecificConfig? {
        func objectType() -> Int? {
            guard let value = reader.readBits(5) else { return nil }
            if value == 31 { return reader.readBits(6).map { 32 + Int($0) } }
            return Int(value)
        }
        /// The frequency in Hz; 0 for a reserved index; nil when the bits run out.
        func frequency() -> Int? {
            guard let index = reader.readBits(4) else { return nil }
            if index == 0xF { return reader.readBits(24).map { Int($0) } }
            let i = Int(index)
            return i < aacSamplingFrequencies.count ? aacSamplingFrequencies[i] : 0
        }
        guard var type = objectType(), let rate = frequency(),
              let channels = reader.readBits(4) else { return nil }
        var outputRate = rate
        var configuration = Int(channels)
        var coreType = type
        if type == 5 || type == 29 {
            // Explicit SBR/PS signalling: the extension rate is the output rate.
            guard let extensionRate = frequency(), let core = objectType() else { return nil }
            outputRate = extensionRate
            coreType = core
            if core == 22 { _ = reader.readBits(4) }  // extensionChannelConfiguration (ER BSAC)
            // Parametric Stereo decodes a mono core to stereo.
            if type == 29, configuration == 1 { configuration = 2 }
            type = AudioHeaderParser.aacObjectTypes.contains(core) ? type : core
        }
        // GASpecificConfig begins with frameLengthFlag.
        var frameLength: Int?
        switch coreType {
        case 1, 2, 3, 4, 17: frameLength = reader.readBit().map { $0 ? 960 : 1024 }
        case 23, 39: frameLength = reader.readBit().map { $0 ? 480 : 512 }
        default: frameLength = nil
        }
        return AudioSpecificConfig(
            audioObjectType: type, samplingFrequency: outputRate > 0 ? outputRate : nil,
            channelConfiguration: configuration,
            coreSamplingFrequency: rate > 0 ? rate : nil, frameLength: frameLength)
    }

    /// A track from an AudioSpecificConfig; channels are nil for a
    /// channelConfiguration of 0 (layout in a program_config_element, not read).
    static func track(_ config: AudioSpecificConfig, codecTag: String) -> VideoAudioTrack {
        let layout = aacChannels(config.channelConfiguration)
        return VideoAudioTrack(
            format: config.format, codecTag: codecTag,
            samplingFrequency: config.samplingFrequency,
            channelCount: layout?.count, hasLFE: layout?.lfe)
    }

    // MARK: LATM / LOAS (ISO/IEC 14496-3 1.7; MPEG-TS stream_type 0x11)

    /// The first AudioSpecificConfig carried in a LOAS AudioSyncStream
    /// (ISO/IEC 14496-3 1.7.2): syncword 0x2B7 (11 bits), audioMuxLengthBytes
    /// (13), then AudioMuxElement(1), whose useSameStreamMux bit is 0 when a
    /// StreamMuxConfig (1.7.3) follows.
    ///
    /// Only the common case is read: audioMuxVersionA 0 and one program with one
    /// layer (numProgram 0, numLayer 0), where the first AudioSpecificConfig
    /// follows numLayer directly (audioMuxVersion 0), or after its LatmGetValue()
    /// length (audioMuxVersion 1, after taraBufferFullness). Several programs or
    /// layers in one PID, or audioMuxVersionA 1, return nil: the track then stays
    /// unidentified and "not checked".
    static func findLATMConfig(_ bytes: [UInt8]) -> VideoAudioTrack? {
        var offset = 0
        while offset + 3 <= bytes.count {
            guard bytes[offset] == 0x56, bytes[offset + 1] & 0xE0 == 0xE0 else {
                offset += 1
                continue
            }
            let length = (Int(bytes[offset + 1] & 0x1F) << 8) | Int(bytes[offset + 2])
            let end = offset + 3 + length
            // Confirm with the next syncword where it fits.
            if end + 2 <= bytes.count, !(bytes[end] == 0x56 && bytes[end + 1] & 0xE0 == 0xE0) {
                offset += 1
                continue
            }
            let frame = Array(bytes[(offset + 3)..<min(end, bytes.count)])
            var reader = BitstreamReader(bytes: frame)
            if let useSame = reader.readBit(), !useSame {
                return streamMuxConfig(&reader).map { track($0.config, codecTag: "") }
            }
            // useSameStreamMux: this frame repeats an earlier configuration.
            offset = end
        }
        return nil
    }

    /// The first AudioSpecificConfig of a StreamMuxConfig, common case only
    /// (see ``findLATMConfig(_:)``).
    private static func streamMuxConfig(
        _ reader: inout BitstreamReader
    ) -> (config: AudioSpecificConfig, numSubFrames: Int)? {
        /// LatmGetValue(): bytesForValue (2), then that many plus one bytes.
        func latmValue() -> Int? {
            guard let count = reader.readBits(2) else { return nil }
            var value = 0
            for _ in 0...Int(count) {
                guard let byte = reader.readBits(8) else { return nil }
                value = value << 8 | Int(byte)
            }
            return value
        }
        guard let version = reader.readBit() else { return nil }
        if version {
            guard let versionA = reader.readBit(), !versionA, latmValue() != nil else { return nil }
        }
        // allStreamsSameTimeFraming (1), numSubFrames (6), numProgram (4), numLayer (3).
        guard reader.skipBits(1), let subFrames = reader.readBits(6),
              let programs = reader.readBits(4), programs == 0,
              let layers = reader.readBits(3), layers == 0
        else { return nil }
        if version { guard latmValue() != nil else { return nil } }  // ascLen
        return audioSpecificConfig(&reader).map { ($0, Int(subFrames)) }
    }

    // MARK: Raw MPEG-4 audio (MPEG-TS stream_type 0x1C)

    /// The AudioSpecificConfig of an MPEG-4_audio_extension_descriptor
    /// (ISO/IEC 13818-1, descriptor_tag 46): ASC_flag (1), reserved (3),
    /// num_of_loops (4), one audioProfileLevelIndication byte per loop, then,
    /// when ASC_flag is set, ASC_size (8) and the AudioSpecificConfig. Raw MPEG-4
    /// audio has no transport header of its own, so this descriptor is the only
    /// place its configuration can be read; without it the track stays
    /// unidentified.
    static func mpeg4AudioExtensionDescriptor(_ payload: [UInt8]) -> VideoAudioTrack? {
        guard let first = payload.first, first & 0x80 != 0 else { return nil }
        let sizeIndex = 1 + Int(first & 0x0F)
        guard sizeIndex < payload.count else { return nil }
        let size = Int(payload[sizeIndex])
        let start = sizeIndex + 1
        guard size > 0, start + size <= payload.count,
              let config = audioSpecificConfig(Data(payload[start..<(start + size)]))
        else { return nil }
        return track(config, codecTag: "")
    }

    /// The first ADTS header in a window (ISO/IEC 13818-7 6.2.1).
    static func findADTSHeader(_ bytes: [UInt8], limit: Int = 4096) -> VideoAudioTrack? {
        let end = min(bytes.count - 7, limit)
        guard end >= 0 else { return nil }
        for offset in 0...end {
            guard bytes[offset] == 0xFF, bytes[offset + 1] & 0xF6 == 0xF0 else { continue }
            let rateIndex = Int((bytes[offset + 2] >> 2) & 0x0F)
            guard rateIndex < aacSamplingFrequencies.count else { continue }
            let configuration = Int(((bytes[offset + 2] & 0x01) << 2) | (bytes[offset + 3] >> 6))
            let frameLength = (Int(bytes[offset + 3] & 0x03) << 11)
                | (Int(bytes[offset + 4]) << 3) | Int(bytes[offset + 5] >> 5)
            guard frameLength >= 7 else { continue }
            // Confirm with the next syncword where it fits.
            let next = offset + frameLength
            if next + 2 <= bytes.count, !(bytes[next] == 0xFF && bytes[next + 1] & 0xF6 == 0xF0) {
                continue
            }
            let channels = aacChannels(configuration)
            return VideoAudioTrack(
                format: .aac, codecTag: "",
                samplingFrequency: aacSamplingFrequencies[rateIndex],
                channelCount: channels?.count, hasLFE: channels?.lfe)
        }
        return nil
    }

    // MARK: AAC bit rate over time (D62)

    /// One frame's bits (lower and upper bound) and presentation duration.
    struct TimedFrame: Equatable {
        let lowerBits: Int
        let upperBits: Int
        let duration: Double
    }

    /// The most bits any one-second window of presentation time carries, counting
    /// each frame in the window its start falls in; for a stream shorter than a
    /// second, all its bits.
    static func maximumOneSecondBits(_ frames: [TimedFrame], upper: Bool) -> Int {
        var starts: [Double] = []
        var time = 0.0
        for frame in frames {
            starts.append(time)
            time += frame.duration
        }
        var best = 0, sum = 0, end = 0
        for start in frames.indices {
            while end < frames.count, starts[end] < starts[start] + 1.0 - 1e-9 {
                sum += upper ? frames[end].upperBits : frames[end].lowerBits
                end += 1
            }
            best = max(best, sum)
            sum -= upper ? frames[start].upperBits : frames[start].lowerBits
        }
        return best
    }

    static func measured(_ frames: [TimedFrame], wholeStream: Bool) -> VideoAudioTrack.MeasuredBitRate? {
        guard !frames.isEmpty else { return nil }
        return VideoAudioTrack.MeasuredBitRate(
            lowerBound: maximumOneSecondBits(frames, upper: false),
            upperBound: maximumOneSecondBits(frames, upper: true),
            frameCount: frames.count, coversWholeStream: wholeStream)
    }

    /// Walks the ADTS frames of an elementary stream (ISO/IEC 13818-7 6.2.1; field
    /// layout as FFmpeg `adts_header.c` reads it): each frame is `aac_frame_length`
    /// bytes carrying (`number_of_raw_data_blocks_in_frame` + 1) × 1024 samples at the
    /// header's sampling frequency. Up to ``maximumScannedFrames``.
    ///
    /// - Parameter complete: whether `bytes` is the PID's whole elementary stream.
    static func scanADTSBitRate(_ bytes: [UInt8], complete: Bool) -> VideoAudioTrack.MeasuredBitRate? {
        func header(at offset: Int) -> (length: Int, duration: Double)? {
            guard offset + 7 <= bytes.count, bytes[offset] == 0xFF, bytes[offset + 1] & 0xF6 == 0xF0 else {
                return nil
            }
            let rateIndex = Int((bytes[offset + 2] >> 2) & 0x0F)
            guard rateIndex < aacSamplingFrequencies.count else { return nil }
            let length = (Int(bytes[offset + 3] & 0x03) << 11)
                | (Int(bytes[offset + 4]) << 3) | Int(bytes[offset + 5] >> 5)
            guard length >= 7 else { return nil }
            let blocks = Int(bytes[offset + 6] & 0x03) + 1
            return (length, Double(1024 * blocks) / Double(aacSamplingFrequencies[rateIndex]))
        }
        // The first frame whose successor (where it fits) is also a frame.
        var offset = 0
        while offset + 7 <= bytes.count {
            if let first = header(at: offset),
               offset + first.length + 2 > bytes.count || header(at: offset + first.length) != nil {
                break
            }
            offset += 1
        }
        var frames: [TimedFrame] = []
        var reachedEnd = false
        while frames.count < maximumScannedFrames {
            if offset == bytes.count { reachedEnd = true; break }
            guard let frame = header(at: offset), offset + frame.length <= bytes.count else { break }
            frames.append(TimedFrame(lowerBits: frame.length * 8, upperBits: frame.length * 8,
                                     duration: frame.duration))
            offset += frame.length
        }
        return measured(frames, wholeStream: complete && reachedEnd)
    }

    /// Walks the LOAS AudioSyncStream of an elementary stream (ISO/IEC 14496-3
    /// 1.7.2: syncword 0x2B7, audioMuxLengthBytes, AudioMuxElement). Each element
    /// carries numSubFrames + 1 frames of the configured frame length at the core
    /// sampling frequency (from its StreamMuxConfig, common case only — see
    /// ``findLATMConfig(_:)``). Up to ``maximumScannedFrames`` elements.
    static func scanLATMBitRate(_ bytes: [UInt8], complete: Bool) -> VideoAudioTrack.MeasuredBitRate? {
        func isSync(_ offset: Int) -> Bool {
            offset + 3 <= bytes.count && bytes[offset] == 0x56 && bytes[offset + 1] & 0xE0 == 0xE0
        }
        var offset = 0
        while offset + 3 <= bytes.count, !isSync(offset) { offset += 1 }
        var duration: Double?
        var frames: [TimedFrame] = []
        var skippedBeforeConfig = false
        var reachedEnd = false
        while frames.count < maximumScannedFrames {
            if offset == bytes.count { reachedEnd = true; break }
            guard isSync(offset) else { break }
            let length = (Int(bytes[offset + 1] & 0x1F) << 8) | Int(bytes[offset + 2])
            let end = offset + 3 + length
            guard length > 0, end <= bytes.count else { break }
            var reader = BitstreamReader(bytes: Array(bytes[(offset + 3)..<end]))
            guard let useSame = reader.readBit() else { break }
            if !useSame {
                guard let mux = streamMuxConfig(&reader),
                      let rate = mux.config.coreSamplingFrequency,
                      let frameLength = mux.config.frameLength else { return nil }
                duration = Double((mux.numSubFrames + 1) * frameLength) / Double(rate)
            }
            if let duration {
                // Payload ≥ element − 1 bit (useSameStreamMux) − PayloadLengthInfo
                // (at most length / 255 + 1 bytes) − byte alignment (< 1 byte).
                let lower = useSame ? max(0, length - 2 - length / 255) * 8 : 0
                frames.append(TimedFrame(lowerBits: lower, upperBits: length * 8, duration: duration))
            } else {
                skippedBeforeConfig = true
            }
            offset = end
        }
        return measured(frames, wholeStream: complete && reachedEnd && !skippedBeforeConfig)
    }

    // MARK: AC-3 (ETSI TS 102 366 4.3 syncinfo/bsi; Annex F dac3)

    static let ac3BitRates = [
        32, 40, 48, 56, 64, 80, 96, 112, 128, 160, 192, 224, 256, 320, 384, 448, 512, 576, 640,
    ]
    static let ac3SamplingFrequencies = [48000, 44100, 32000]
    /// Full-bandwidth channels per acmod (Table 4.3); acmod 0 is 1+1 dual mono.
    static let ac3Channels = [2, 1, 2, 3, 3, 4, 4, 5]

    static func ac3Track(fscod: Int, acmod: Int, lfeon: Bool, bitRateCode: Int?,
                         codecTag: String, pid: Int? = nil) -> VideoAudioTrack {
        let rate = fscod < 3 ? ac3SamplingFrequencies[fscod] : nil
        let bitRate = bitRateCode.flatMap { $0 < ac3BitRates.count ? ac3BitRates[$0] * 1000 : nil }
        return VideoAudioTrack(
            format: .ac3, codecTag: codecTag, pid: pid,
            samplingFrequency: rate,
            channelCount: ac3Channels[acmod & 7] + (lfeon ? 1 : 0),
            hasLFE: lfeon, isDualMono: acmod == 0,
            maximumBitRate: bitRate, frameBitRate: bitRate)
    }

    /// Parses an AC3SpecificBox (`dac3`) payload.
    static func dac3(_ bytes: [UInt8], codecTag: String) -> VideoAudioTrack? {
        guard bytes.count >= 3 else { return nil }
        let bits = (Int(bytes[0]) << 16) | (Int(bytes[1]) << 8) | Int(bytes[2])
        return ac3Track(
            fscod: (bits >> 22) & 0x03, acmod: (bits >> 11) & 0x07,
            lfeon: (bits >> 10) & 0x01 == 1, bitRateCode: (bits >> 5) & 0x1F,
            codecTag: codecTag)
    }

    /// The first AC-3 syncframe header in a window.
    static func findAC3Header(_ bytes: [UInt8], limit: Int = 4096) -> VideoAudioTrack? {
        let end = min(bytes.count - 8, limit)
        guard end >= 0 else { return nil }
        for offset in 0...end {
            guard bytes[offset] == 0x0B, bytes[offset + 1] == 0x77 else { continue }
            var reader = BitstreamReader(bytes: Array(bytes[(offset + 4)...]))
            guard let fscod = reader.readBits(2), let frmsizecod = reader.readBits(6),
                  let bsid = reader.readBits(5), reader.skipBits(3),
                  let acmod = reader.readBits(3)
            else { continue }
            guard fscod != 3, frmsizecod < 38, bsid <= 10 else { continue }
            if acmod & 0x1 != 0, acmod != 0x1 { _ = reader.skipBits(2) }  // cmixlev
            if acmod & 0x4 != 0 { _ = reader.skipBits(2) }                // surmixlev
            if acmod == 0x2 { _ = reader.skipBits(2) }                    // dsurmod
            guard let lfeon = reader.readBit() else { continue }
            return ac3Track(
                fscod: Int(fscod), acmod: Int(acmod), lfeon: lfeon,
                bitRateCode: Int(frmsizecod >> 1), codecTag: "")
        }
        return nil
    }

    // MARK: LPCM in MPEG-2 TS

    /// The 4-byte LPCM header at the start of an HDMV (Blu-ray) LPCM PES payload:
    /// payload size (16), channel_assignment (4), sampling_frequency (4),
    /// bits_per_sample (2). Not a public standard; the field layout is the one
    /// documented by open-source demultiplexers.
    static func hdmvLPCM(_ bytes: [UInt8]) -> VideoAudioTrack? {
        guard bytes.count >= 4 else { return nil }
        let assignment = Int(bytes[2] >> 4)
        let rateCode = Int(bytes[2] & 0x0F)
        let bitsCode = Int(bytes[3] >> 6)
        let channels: [Int: (Int, Bool)] = [
            1: (1, false), 3: (2, false), 4: (3, false), 5: (3, false), 6: (4, false),
            7: (4, false), 8: (5, false), 9: (6, true), 10: (7, false), 11: (8, true),
        ]
        let rates = [1: 48000, 4: 96000, 5: 192000]
        let bits = [1: 16, 2: 20, 3: 24]
        let layout = channels[assignment]
        let rate = rates[rateCode]
        let depth = bits[bitsCode]
        var bitRate: Int?
        if let layout, let rate, let depth { bitRate = layout.0 * rate * depth }
        return VideoAudioTrack(
            format: .lpcm, codecTag: "",
            samplingFrequency: rate, channelCount: layout?.0, hasLFE: layout?.1,
            bitsPerSample: depth, maximumBitRate: bitRate)
    }

    /// The 4-byte SMPTE ST 302 AES3 header: audio_packet_size (16),
    /// number_channels (2), channel_identification (8), bits_per_sample (2).
    /// ST 302 fixes the sampling frequency at 48 kHz.
    static func smpte302(_ bytes: [UInt8]) -> VideoAudioTrack? {
        guard bytes.count >= 4 else { return nil }
        let channels = [2, 4, 6, 8][Int(bytes[2] >> 6)]
        let bitsCode = Int((bytes[3] >> 4) & 0x03)
        let depth = bitsCode < 3 ? [16, 20, 24][bitsCode] : nil
        return VideoAudioTrack(
            format: .lpcm, codecTag: "",
            samplingFrequency: 48000, channelCount: channels,
            bitsPerSample: depth,
            maximumBitRate: depth.map { channels * 48000 * $0 })
    }
}

extension VideoAudioTrack {
    /// A copy carrying container-level identification.
    func with(codecTag: String, pid: Int?) -> VideoAudioTrack {
        VideoAudioTrack(
            format: format, codecTag: codecTag, pid: pid,
            samplingFrequency: samplingFrequency, channelCount: channelCount,
            hasLFE: hasLFE, isDualMono: isDualMono, bitsPerSample: bitsPerSample,
            maximumBitRate: maximumBitRate, averageBitRate: averageBitRate,
            frameBitRate: frameBitRate, bitRateScan: bitRateScan, measuredBitRate: measuredBitRate)
    }

    /// A copy carrying the result of a frame-by-frame bit rate walk.
    func with(bitRateScan scan: BitRateScan?) -> VideoAudioTrack {
        VideoAudioTrack(
            format: format, codecTag: codecTag, pid: pid,
            samplingFrequency: samplingFrequency, channelCount: channelCount,
            hasLFE: hasLFE, isDualMono: isDualMono, bitsPerSample: bitsPerSample,
            maximumBitRate: maximumBitRate, averageBitRate: averageBitRate,
            frameBitRate: frameBitRate, bitRateScan: scan, measuredBitRate: measuredBitRate)
    }

    /// A copy carrying an AAC frame walk's measured bit rate (D62).
    func with(measuredBitRate measured: MeasuredBitRate?) -> VideoAudioTrack {
        VideoAudioTrack(
            format: format, codecTag: codecTag, pid: pid,
            samplingFrequency: samplingFrequency, channelCount: channelCount,
            hasLFE: hasLFE, isDualMono: isDualMono, bitsPerSample: bitsPerSample,
            maximumBitRate: maximumBitRate, averageBitRate: averageBitRate,
            frameBitRate: frameBitRate, bitRateScan: bitRateScan, measuredBitRate: measured)
    }
}
