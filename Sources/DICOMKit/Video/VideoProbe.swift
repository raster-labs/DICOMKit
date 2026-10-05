// NEMA-verified: 2026a, checked 2026-10-01 — no DICOM-standard data (container probing); a raw MPEG-2 video elementary stream (sequence header 00 00 01 B3) is recognised before the H.264/HEVC parameter-set search, so it is offered to the MPEG2 MP@ML / MP@HL syntaxes of PS3.5 2026a 8.2.5 / 8.2.6 (D179); audio tracks read from MP4 and MPEG-TS for the PS3.5 2026a 8.2.5/8.2.12 (Table 8.2.12-1) check, which VideoConformanceValidator.validateAudio applies (D46)
//
// VideoProbe.swift
// DICOMKit
//
// Copyright © 2026 DICOMKit. All rights reserved.
//

import Foundation
import DICOMCore

/// Everything known about a video input before deciding whether to encapsulate it.
public struct VideoProbeResult: Sendable {
    /// The container the payload arrived in.
    public let container: VideoContainer
    /// What the coded bit stream says about itself.
    public let stream: VideoStreamInfo
    /// Frame count: exact from a container's sample table, counted from access
    /// units for a raw elementary stream.
    public let frameCount: Int
    /// How the frame count was obtained, which matters because one source is
    /// exact and the other is a scan.
    public let frameCountSource: FrameCountSource
    /// The number of audio tracks: `soun` tracks in an MP4, audio PIDs in an
    /// MPEG-TS (read only with `trustInput`, the one way a TS is probed).
    ///
    /// DICOM video may carry audio in the encapsulated bit stream (PS3.5 8.2.5,
    /// 8.2.7-8.2.11, and 8.2.12 Table 8.2.12-1), so a non-zero count is not a
    /// defect: `convert` keeps the tracks. Always 0 for an elementary stream,
    /// which has no audio. Equal to `audioTracks.count`.
    public let audioTrackCount: Int
    /// The audio tracks with the parameters their container exposes, for the
    /// PS3.5 8.2.5 / 8.2.12 check (``VideoConformanceValidator/validateAudio(tracks:container:transferSyntax:)``).
    ///
    /// A result built with the `audioTrackCount:` initializer holds that many
    /// ``VideoAudioTrack/unidentified`` entries.
    public let audioTracks: [VideoAudioTrack]
    /// The audio tracks as plain stream descriptions (format, rate, channels, bit rate).
    public var audioStreams: [AudioStreamInfo] { audioTracks.map(\.streamInfo) }
    /// The display rotation the container asks a player to apply, in degrees
    /// clockwise. DICOM cannot record it, so non-zero values are warned about.
    public let rotationDegrees: Int
    /// The transfer syntax that fits this stream, when one does.
    public let suggestedTransferSyntax: TransferSyntax?

    /// Where a frame count came from.
    public enum FrameCountSource: String, Sendable {
        /// The container's sample table: exact and cheap.
        case sampleTable
        /// Counted access units in the bit stream: the raw-stream fallback.
        case accessUnitScan
        /// No reliable count was available.
        case unavailable
    }

    /// The effective frame rate, preferring the bit stream's own declaration over
    /// the container's, since the container's is derived from durations.
    public let frameRate: Double?

    /// The MPEG-2 Program Stream / PES wrapping the elementary stream was read from
    /// (PS3.5 2026a 8.2.5 / 8.2.6), when ``container`` is ``VideoContainer/elementaryStream``
    /// because of one; nil otherwise.
    public let mpeg2SystemsLayer: MPEG2SystemsLayer?

    /// The container as it should be named: the MPEG-2 systems layer when there is one,
    /// else ``VideoContainer/displayName``.
    public var containerDisplayName: String {
        mpeg2SystemsLayer?.displayName ?? container.displayName
    }

    public init(
        container: VideoContainer,
        stream: VideoStreamInfo,
        frameCount: Int,
        frameCountSource: FrameCountSource,
        audioTrackCount: Int,
        suggestedTransferSyntax: TransferSyntax?,
        frameRate: Double?,
        audioTracks: [AudioStreamInfo] = [],
        rotationDegrees: Int = 0
    ) {
        self.init(
            container: container, stream: stream, frameCount: frameCount,
            frameCountSource: frameCountSource,
            audioTracks: audioTracks.isEmpty
                ? Array(repeating: .unidentified, count: max(0, audioTrackCount))
                : audioTracks.map(VideoAudioTrack.init),
            suggestedTransferSyntax: suggestedTransferSyntax, frameRate: frameRate,
            rotationDegrees: rotationDegrees)
    }

    public init(
        container: VideoContainer,
        stream: VideoStreamInfo,
        frameCount: Int,
        frameCountSource: FrameCountSource,
        audioTracks: [VideoAudioTrack],
        suggestedTransferSyntax: TransferSyntax?,
        frameRate: Double?,
        mpeg2SystemsLayer: MPEG2SystemsLayer? = nil,
        rotationDegrees: Int = 0
    ) {
        self.mpeg2SystemsLayer = mpeg2SystemsLayer
        self.container = container
        self.stream = stream
        self.frameCount = frameCount
        self.frameCountSource = frameCountSource
        self.audioTrackCount = audioTracks.count
        self.audioTracks = audioTracks
        self.rotationDegrees = rotationDegrees
        self.suggestedTransferSyntax = suggestedTransferSyntax
        self.frameRate = frameRate
    }
}

/// Why an input could not be probed.
public enum VideoProbeError: Error, Sendable, Equatable {
    /// The bytes match no container or elementary stream this toolkit reads.
    case unrecognizedFormat
    /// The container holds no video track.
    case noVideoTrack
    /// The container holds more than one video track, so picking one silently
    /// would be a guess.
    case multipleVideoTracks(count: Int)
    /// The codec is not one DICOM video carries.
    case unsupportedCodec(String)
    /// Parameter sets were missing or unreadable, so nothing can be validated.
    case parameterSetsUnreadable
    /// A transport stream whose video PID could not be demultiplexed - no
    /// PAT/PMT, a scrambled PID, or no readable parameter sets - so it cannot be
    /// validated.
    case transportStreamNotValidatable
    /// The input is multi-frame but not video, and belongs to a different tool.
    case notVideo(detected: String)

    /// A message naming the problem and, where one exists, the remedy.
    public var message: String {
        switch self {
        case .unrecognizedFormat:
            return """
                error: the input is not a recognized video container or elementary stream.
                       dicom-video reads MP4, MOV, MPEG-TS, and raw H.264/HEVC/MPEG-2 streams.
                """
        case .noVideoTrack:
            return "error: the container holds no video track."
        case let .multipleVideoTracks(count):
            return """
                error: the container holds \(count) video tracks; \
                dicom-video will not guess which one to convert.

                       Extract the track you want first:
                         ffmpeg -i input.mp4 -map 0:v:0 -c copy track0.mp4
                """
        case let .unsupportedCodec(name):
            return """
                error: \(name) is not a DICOM video codec.
                       dicom-video handles H.264, HEVC and MPEG-2 only.
                """
        case .parameterSetsUnreadable:
            return """
                error: the video track's parameter sets could not be read, so the \
                stream cannot be validated.
                """
        case .transportStreamNotValidatable:
            return """
                error: the MPEG-2 Transport Stream's video could not be demultiplexed                 (no PAT/PMT, a scrambled PID, or unreadable parameter sets), so it cannot                 be validated.
                       Either remux it:
                         ffmpeg -i input.ts -map 0:v:0 -map '0:a?' -c copy output.ts
                       or re-run with --trust-input to encapsulate the TS unvalidated.
                """
        case let .notVideo(detected):
            return """
                error: the input is \(detected), not a video bitstream.
                       dicom-video handles H.264/HEVC/MPEG-2 only. Use dicom-image instead.
                """
        }
    }
}

/// Probes a video input, deriving every DICOM attribute from the bytes rather
/// than from the caller.
///
/// This is deliberately free of any platform framework: identifying, validating
/// and passing through an already-conformant payload works everywhere. Rewriting
/// a container is the only part that needs more.
public enum VideoProbe {

    /// File signatures for formats that are multi-frame but are not video, so the
    /// rejection can name what was actually supplied.
    ///
    /// These belong to a different DICOM storage path entirely.
    private static let nonVideoSignatures: [(bytes: [UInt8], name: String)] = [
        ([0x89, 0x50, 0x4E, 0x47], "a PNG image"),
        ([0xFF, 0xD8, 0xFF], "a JPEG image"),
        ([0x47, 0x49, 0x46, 0x38], "an animated GIF"),
        ([0x49, 0x49, 0x2A, 0x00], "a TIFF image"),
        ([0x4D, 0x4D, 0x00, 0x2A], "a TIFF image"),
        ([0x42, 0x4D], "a BMP image"),
        ([0x52, 0x49, 0x46, 0x46], "a RIFF/AVI file"),
        ([0x1A, 0x45, 0xDF, 0xA3], "a Matroska/WebM file"),
        ([0x44, 0x49, 0x43, 0x4D], "a DICOM file"),
    ]

    /// Identifies a non-video input by signature, so the caller can redirect to
    /// the right tool rather than attempting a conversion.
    public static func detectNonVideo(_ data: Data) -> String? {
        // A DICOM file's magic sits at offset 128, after the preamble.
        if data.count > 132 {
            let magic = [UInt8](data[(data.startIndex + 128)..<(data.startIndex + 132)])
            if magic == [0x44, 0x49, 0x43, 0x4D] { return "a DICOM file" }
        }
        let prefix = [UInt8](data.prefix(8))
        for signature in nonVideoSignatures {
            guard prefix.count >= signature.bytes.count else { continue }
            if Array(prefix.prefix(signature.bytes.count)) == signature.bytes {
                return signature.name
            }
        }
        return nil
    }

    /// Probes an input.
    ///
    /// - Parameters:
    ///   - data: The input bytes.
    ///   - trustInput: Skip deep validation for a transport stream, encapsulating
    ///     it on the caller's assertion that it is conformant.
    /// - Returns: What was found.
    /// - Throws: ``VideoProbeError`` when the input cannot be probed at all.
    public static func probe(_ data: Data, trustInput: Bool = false) throws -> VideoProbeResult {
        // Reject non-video input first, so the message names the real format
        // rather than complaining about a missing start code.
        if let detected = detectNonVideo(data) {
            throw VideoProbeError.notVideo(detected: detected)
        }

        let container = MP4ContainerParser.detectContainer(data)
        switch container {
        case .mp4, .quickTime:
            return try probeISOBMFF(data, container: container)
        case .mpegTS:
            if let result = probeTransportStream(data) { return result }
            guard trustInput else { throw VideoProbeError.transportStreamNotValidatable }
            return try probeTrustedTransportStream(data)
        case .elementaryStream:
            // MPEG-PS / MPEG-PES (PS3.5 2026a 8.2.5, 8.2.6): probe the video PES payloads;
            // the payload encapsulated is still the systems stream as given.
            if let layer = MP4ContainerParser.mpeg2SystemsLayer(data) {
                guard let elementary = MP4ContainerParser.mpeg2VideoElementaryStream(data) else {
                    throw VideoProbeError.noVideoTrack
                }
                let inner = try probeElementaryStream(elementary)
                let audio = MP4ContainerParser.mpeg2AudioStreamIDs(data)
                return VideoProbeResult(
                    container: .elementaryStream,
                    stream: inner.stream,
                    frameCount: inner.frameCount,
                    frameCountSource: inner.frameCountSource,
                    audioTracks: Array(repeating: .unidentified, count: audio.count),
                    suggestedTransferSyntax: inner.suggestedTransferSyntax,
                    frameRate: inner.frameRate,
                    mpeg2SystemsLayer: layer)
            }
            return try probeElementaryStream(data)
        case .unknown:
            throw VideoProbeError.unrecognizedFormat
        }
    }

    // MARK: - ISO-BMFF

    private static func probeISOBMFF(
        _ data: Data,
        container: VideoContainer
    ) throws -> VideoProbeResult {
        guard let info = MP4ContainerParser.inspect(data) else {
            throw VideoProbeError.unrecognizedFormat
        }
        guard !info.videoTracks.isEmpty else { throw VideoProbeError.noVideoTrack }
        guard info.videoTracks.count == 1 else {
            throw VideoProbeError.multipleVideoTracks(count: info.videoTracks.count)
        }

        let track = info.videoTracks[0]
        guard track.codec != .unknown else {
            throw VideoProbeError.unsupportedCodec("this track's codec")
        }
        guard !track.parameterSets.isEmpty else {
            throw VideoProbeError.parameterSetsUnreadable
        }

        // Parse the parameter sets from the sample description. This is read-only:
        // the bytes written are the container's own.
        let stream: VideoStreamInfo
        switch track.codec {
        case .h264:
            // avcC stores each parameter set as a complete NAL unit, header byte
            // included, so the header has to be validated and stripped first.
            // An MVC-only sample entry carries just the subset SPS.
            guard let sps = track.parameterSets.compactMap({ H264Parser.parseSPS(nalUnit: $0) }).first
                ?? H264Parser.firstSubsetSPS(in: track.parameterSets)
            else { throw VideoProbeError.parameterSetsUnreadable }
            stream = refineH264(
                sps.streamInfo,
                nalUnits: track.subsetParameterSets + track.parameterSets + track.leadingNALUnits
            )
        case .h265:
            // hvcC keeps the two-byte NAL header on each stored unit.
            guard let sps = track.parameterSets.compactMap({ HEVCParser.parseSPS(nalUnit: $0) }).first
            else { throw VideoProbeError.parameterSetsUnreadable }
            stream = sps.streamInfo
        case .mpeg2:
            guard let header = track.parameterSets.compactMap({ MPEG2Parser.parseSequenceHeader($0) }).first
            else { throw VideoProbeError.parameterSetsUnreadable }
            stream = header.streamInfo
        case .unknown:
            throw VideoProbeError.unsupportedCodec("this track's codec")
        }

        // Prefer the bit stream's own frame rate; fall back to the container's,
        // which is derived from sample durations.
        let frameRate = stream.frameRate ?? track.frameRate
        let resolved = stream.with(frameRate: frameRate)

        return VideoProbeResult(
            container: container,
            stream: resolved,
            frameCount: track.frameCount,
            frameCountSource: track.frameCount > 0 ? .sampleTable : .unavailable,
            audioTracks: info.audioTracks,
            suggestedTransferSyntax: VideoConformanceValidator.selectTransferSyntax(
                for: resolved, payloadByteCount: data.count),
            frameRate: frameRate,
            rotationDegrees: track.rotationDegrees
        )
    }

    // MARK: - Elementary Streams

    private static func probeElementaryStream(_ data: Data) throws -> VideoProbeResult {
        // An MPEG-2 video elementary stream starts with a sequence header, start code
        // 00 00 01 B3 (ITU-T H.262 6.2.2.1). It is checked first: MPEG-2 slice start
        // codes 0x07, 0x27, … read as H.264 NAL type 7 (SPS), so trying H.264 first
        // reported a raw .m2v as H.264 with a nonsense profile and level.
        if firstStartCodeValue(in: data) == 0xB3, let header = MPEG2Parser.parseSequenceHeader(data) {
            return mpeg2ElementaryStreamResult(header: header, data: data)
        }

        // Try each codec's parameter set in turn. Detection is by content, since
        // an extension is a claim rather than evidence.
        if let sps = H264Parser.parseFirstSPS(annexB: data) {
            let stream = refineH264(sps.streamInfo, nalUnits: NALUnit.splitAnnexB(data))
            let count = H264Parser.countFrames(annexB: data)
            return VideoProbeResult(
                container: .elementaryStream,
                stream: stream,
                frameCount: count,
                frameCountSource: count > 0 ? .accessUnitScan : .unavailable,
                audioTrackCount: 0,
                suggestedTransferSyntax: VideoConformanceValidator.selectTransferSyntax(for: stream),
                frameRate: stream.frameRate
            )
        }

        if let sps = HEVCParser.parseFirstSPS(annexB: data) {
            let stream = sps.streamInfo
            let count = HEVCParser.countFrames(annexB: data)
            return VideoProbeResult(
                container: .elementaryStream,
                stream: stream,
                frameCount: count,
                frameCountSource: count > 0 ? .accessUnitScan : .unavailable,
                audioTrackCount: 0,
                suggestedTransferSyntax: VideoConformanceValidator.selectTransferSyntax(for: stream),
                frameRate: stream.frameRate
            )
        }

        if let header = MPEG2Parser.parseSequenceHeader(data) {
            return mpeg2ElementaryStreamResult(header: header, data: data)
        }

        throw VideoProbeError.unrecognizedFormat
    }

    private static func mpeg2ElementaryStreamResult(
        header: MPEG2Parser.SequenceHeader,
        data: Data
    ) -> VideoProbeResult {
        let stream = header.streamInfo
        let count = MPEG2Parser.countFrames(data)
        return VideoProbeResult(
            container: .elementaryStream,
            stream: stream,
            frameCount: count,
            frameCountSource: count > 0 ? .accessUnitScan : .unavailable,
            audioTrackCount: 0,
            suggestedTransferSyntax: VideoConformanceValidator.selectTransferSyntax(for: stream),
            frameRate: stream.frameRate
        )
    }

    /// The byte after the first 00 00 01 start-code prefix, or nil when there is none
    /// in the first 1024 bytes.
    static func firstStartCodeValue(in data: Data) -> UInt8? {
        let bytes = data.prefix(1024)
        var index = bytes.startIndex
        while index + 3 < bytes.endIndex {
            if bytes[index] == 0, bytes[index + 1] == 0, bytes[index + 2] == 1 {
                return bytes[index + 3]
            }
            index += 1
        }
        return nil
    }

    // MARK: - Transport Streams

    /// Probes a transport stream by demultiplexing it: parameter sets and
    /// picture count from the whole video PID, the frame rate from the stream
    /// or, failing that, the PES timestamps, and the audio from its PIDs.
    ///
    /// - Returns: The result, or nil when the video cannot be demultiplexed.
    private static func probeTransportStream(_ data: Data) -> VideoProbeResult? {
        guard let demuxed = TransportStreamScanner.demux(data) else { return nil }
        let video = demuxed.videoElementaryStream

        var stream: VideoStreamInfo
        let frameCount: Int
        switch demuxed.codec {
        case .h264:
            guard let sps = H264Parser.parseFirstSPS(annexB: video) else { return nil }
            var units = NALUnit.splitAnnexB(video)
            if let mvc = demuxed.mvcSubBitstream { units += NALUnit.splitAnnexB(mvc) }
            stream = refineH264(sps.streamInfo, nalUnits: units)
            frameCount = H264Parser.countFrames(annexB: video)
        case .h265:
            guard let sps = HEVCParser.parseFirstSPS(annexB: video) else { return nil }
            stream = sps.streamInfo
            frameCount = HEVCParser.countFrames(annexB: video)
        case .mpeg2:
            guard let header = MPEG2Parser.parseSequenceHeader(video) else { return nil }
            stream = header.streamInfo
            frameCount = MPEG2Parser.countFrames(video)
        case .unknown:
            return nil
        }

        let frameRate = stream.frameRate
            ?? TransportStreamScanner.frameRate(fromTimestamps: demuxed.presentationTimestamps)
        stream = stream.with(frameRate: frameRate)

        return VideoProbeResult(
            container: .mpegTS,
            stream: stream,
            frameCount: frameCount,
            frameCountSource: frameCount > 0 ? .accessUnitScan : .unavailable,
            audioTracks: demuxed.audio,
            suggestedTransferSyntax: VideoConformanceValidator.selectTransferSyntax(
                for: stream, payloadByteCount: data.count),
            frameRate: frameRate
        )
    }

    /// Accepts a transport stream on the caller's assertion, without validating it.
    ///
    /// MPEG-TS is one of the two containers PS3.5 blesses, so passing a conformant
    /// one through is legal. Demuxing it — which is what validation would require —
    /// is a separate piece of work.
    private static func probeTrustedTransportStream(_ data: Data) throws -> VideoProbeResult {
        // Geometry is read even here, because Rows and Columns are required
        // attributes: an object carrying zeroes is one no reader can display, so
        // "trusted" cannot extend to inventing a frame size. Only the conformance
        // checks are skipped, which is what the caller actually asked for.
        // Audio PIDs are listed from the PMT; the check of their parameters is
        // a warning, so it applies even to a stream taken on trust.
        let audioTracks = TransportStreamScanner.audioTracks(data)
        if let payload = TransportStreamScanner.firstVideoPayload(data),
           let stream = elementaryStreamInfo(payload.data, codec: payload.codec) {
            return VideoProbeResult(
                container: .mpegTS,
                stream: stream,
                frameCount: 0,
                frameCountSource: .unavailable,
                audioTracks: audioTracks,
                suggestedTransferSyntax: nil,
                frameRate: stream.frameRate
            )
        }

        // The PID carried something this toolkit cannot read. The stream is still
        // encapsulated on the caller's assertion, but nothing is claimed about it.
        let unknownStream = VideoStreamInfo(
            codec: .unknown, width: 0, height: 0,
            profileIDC: 0, levelTimesTen: 0,
            chromaFormat: .yuv420, bitDepthLuma: 8, bitDepthChroma: 8,
            frameRate: nil, isProgressive: true
        )
        return VideoProbeResult(
            container: .mpegTS,
            stream: unknownStream,
            frameCount: 0,
            frameCountSource: .unavailable,
            audioTracks: audioTracks,
            suggestedTransferSyntax: nil,
            frameRate: nil
        )
    }

    // MARK: - Private

    /// Reads an elementary stream's geometry using the parser for a codec the
    /// container has already declared.
    ///
    /// Content sniffing is deliberately avoided: MPEG-2 start codes share the
    /// Annex B prefix, so an MPEG-2 sequence header parses as a plausible but
    /// wrong H.264 SPS. Where a container names the codec, that name is used.
    private static func elementaryStreamInfo(
        _ data: Data,
        codec: VideoCodec
    ) -> VideoStreamInfo? {
        switch codec {
        case .h264: return H264Parser.parseFirstSPS(annexB: data)?.streamInfo
        case .h265: return HEVCParser.parseFirstSPS(annexB: data)?.streamInfo
        case .mpeg2: return MPEG2Parser.parseSequenceHeader(data)?.streamInfo
        case .unknown: return nil
        }
    }

    /// Adds what only the NAL units beyond the base SPS reveal about an H.264
    /// stream: an MVC subset SPS makes it Stereo High (profile and level taken
    /// from the dependent view's description), and a frame packing SEI makes it
    /// frame-packed 3D.
    static func refineH264(_ stream: VideoStreamInfo, nalUnits: [Data]) -> VideoStreamInfo {
        var refined = stream.with(hasFramePacking: H264Parser.containsFramePackingSEI(nalUnits))
        if let subset = H264Parser.firstSubsetSPS(in: nalUnits),
           subset.profileIDC == H264Parser.stereoHighProfileIDC {
            refined = refined.with(profileIDC: subset.profileIDC, levelTimesTen: subset.levelIDC)
        }
        return refined
    }
}
