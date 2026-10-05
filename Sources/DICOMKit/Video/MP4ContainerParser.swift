// NEMA-verified: 2026a, checked 2026-09-30 — MP3 sample headers walked via stsz/stsc/stco for "CBR MPEG-1 LAYER III" (PS3.5 2026a 8.2.5, 8.2.12, verified by script); compressed audio's template samplesize (ISO/IEC 14496-12) no longer read as bits per sample (D58)
// NEMA-verified: 2026a, checked 2026-10-01 — container rule per codec: MPEG-TS or MP4 for H.264/HEVC (PS3.5 2026a 8.2.7-8.2.11), unconstrained for MPEG-2 (8.2.5, 8.2.6: "The container format for the video bit stream is not constrained") (D177); container syntax is ISO/IEC 14496-12/-14 (out of scope); audio tracks are permitted in the MP4 container per PS3.5 2026a 8.2.7-8.2.11 and Table 8.2.12-1 and are now read (format, sampling frequency, channels, bits per sample, bit rate) for the PS3.5 8.2.5/8.2.12 check, described via PS3.3 Table C.7-13 (003A,0300) (P-VIDEO, D46)
//
// MP4ContainerParser.swift
// DICOMKit
//
// Copyright © 2026 DICOMKit. All rights reserved.
//

import Foundation

/// The container a video payload arrives in.
///
/// PS3.5 Sections 8.2.7 to 8.2.11 (H.264 and HEVC) each state that "the container
/// format for the video bit stream shall be MPEG-2 Transport Stream, a.k.a. MPEG-TS …
/// or MPEG-4, a.k.a. MP4 container", so the encapsulated payload *retains* its
/// container rather than being demuxed to an elementary stream. For MPEG-2 (8.2.5,
/// 8.2.6) "the container format for the video bit stream is not constrained"
/// (MPEG-TS, MPEG-PS, MPEG-ES, MPEG-PES or MP4, for example).
public enum VideoContainer: Sendable, Hashable {
    /// ISO Base Media File Format with an MP4-compatible brand.
    case mp4
    /// QuickTime movie. Structurally an ISO-BMFF file, but not an MP4 brand, so it
    /// must be remuxed before encapsulation.
    case quickTime
    /// MPEG-2 Transport Stream.
    case mpegTS
    /// A raw Annex B / MPEG-2 elementary stream with no container at all. An MPEG-2
    /// Program Stream or Packetized Elementary Stream (PS3.5 2026a 8.2.5 / 8.2.6) is also
    /// reported as this case; ``MP4ContainerParser/mpeg2SystemsLayer(_:)`` tells them apart.
    case elementaryStream
    /// Something this toolkit does not recognize.
    case unknown

    /// Whether DICOM permits this container for an H.264 or HEVC payload (PS3.5 8.2.7-8.2.11).
    @available(*, deprecated, renamed: "isPermittedByDICOM(for:)",
               message: "The container rule depends on the codec: PS3.5 2026a 8.2.5/8.2.6 leave the MPEG-2 container unconstrained")
    public var isPermittedByDICOM: Bool { isPermittedByDICOM(for: .h264) }

    /// Whether DICOM permits this container for a video bit stream coded in `codec`.
    ///
    /// H.264 and HEVC: MPEG-TS or MP4 only (PS3.5 2026a 8.2.7, 8.2.8, 8.2.9, 8.2.10,
    /// 8.2.11). MPEG-2: "The container format for the video bit stream is not
    /// constrained" (8.2.5, 8.2.6), so any container this toolkit can read is
    /// permitted, including a raw elementary stream. An unknown codec (a transport
    /// stream taken on trust) follows the H.264/HEVC rule.
    public func isPermittedByDICOM(for codec: VideoCodec) -> Bool {
        switch (codec, self) {
        case (_, .unknown): return false
        case (.mpeg2, _): return true
        case (_, .mp4), (_, .mpegTS): return true
        case (_, .quickTime), (_, .elementaryStream): return false
        }
    }

    /// A human-readable name for error messages.
    public var displayName: String {
        switch self {
        case .mp4: return "MP4"
        case .quickTime: return "QuickTime (MOV)"
        case .mpegTS: return "MPEG-2 Transport Stream"
        case .elementaryStream: return "raw elementary stream"
        case .unknown: return "unrecognized container"
        }
    }
}

/// Parses the parts of an ISO Base Media File Format file this toolkit needs.
///
/// This is a *reader*, not a muxer: it walks the box tree to identify the codec,
/// recover the parameter sets from `avcC` / `hvcC`, and read the exact frame count
/// from the sample table. Everything here is plain byte handling, so it works on
/// every platform — rewriting a container is the part that needs AVFoundation.
///
/// Reference: ISO/IEC 14496-12 (ISO Base Media File Format),
/// ISO/IEC 14496-14 (MP4), ISO/IEC 14496-15 (AVC/HEVC file format)
public enum MP4ContainerParser {

    // MARK: - Box

    /// One box in the ISO-BMFF tree.
    public struct Box: Sendable, Hashable {
        /// The four-character type, e.g. "moov" or "avcC".
        public let type: String
        /// Offset of the box header within the file.
        public let offset: Int
        /// Total size of the box, header included.
        public let size: Int
        /// Offset of the box's payload, i.e. past its header.
        public let payloadOffset: Int
        /// Size of the box's payload.
        public var payloadSize: Int { size - (payloadOffset - offset) }
    }

    /// What an MP4's video track says about itself.
    public struct TrackInfo: Sendable {
        /// The codec, from the sample entry's four-character code.
        public let codec: VideoCodec
        /// Width in pixels, from the sample description.
        public let width: Int
        /// Height in pixels, from the sample description.
        public let height: Int
        /// Exact frame count from the sample table, which is cheaper and more
        /// reliable than counting access units in the bit stream.
        public let frameCount: Int
        /// Sequence Parameter Sets from `avcC` / `hvcC`, each a complete NAL unit
        /// with its header in place: one byte for AVC, two for HEVC. ISO/IEC
        /// 14496-15 stores whole NAL units in both boxes.
        public let parameterSets: [Data]
        /// Frame rate derived from the media timescale and sample durations.
        public let frameRate: Double?
        /// The rotation the track header's matrix asks a player to apply, in
        /// degrees clockwise (0, 90, 180 or 270).
        ///
        /// DICOM has no attribute for this: Rows and Columns describe the coded
        /// picture, so a rotated clip displays sideways in a DICOM viewer.
        public var rotationDegrees: Int = 0
        /// Subset SPS NAL units from an `mvcC` box, which describe the dependent
        /// view of an MVC stereo stream.
        public var subsetParameterSets: [Data] = []
        /// NAL units from the first few coded pictures, for facts only the
        /// pictures carry - such as a frame packing arrangement SEI.
        public var leadingNALUnits: [Data] = []
    }

    /// A summary of an MP4 file's structure.
    public struct FileInfo: Sendable {
        /// The detected container.
        public let container: VideoContainer
        /// Brands from the `ftyp` box: the major brand first, then compatible ones.
        public let brands: [String]
        /// Video tracks found, in file order.
        public let videoTracks: [TrackInfo]
        /// The number of audio tracks (`soun` handler) in the container.
        ///
        /// DICOM video *can* carry audio: PS3.5 8.2.7–8.2.11 state "Any audio
        /// components included in the data container shall follow the constraints
        /// detailed in 8.2.12", and Table 8.2.12-1 allows AAC, MP3 and MPEG-1 Audio
        /// Layer II in an MP4 container (LPCM and AC-3 only in MPEG-2 TS). PS3.5
        /// 8.2.5 permits CBR MPEG-1 Layer III audio in an MPEG2 stream. Such channels
        /// are described by Multiplexed Audio Channels Description Code Sequence
        /// (003A,0300) in the Cine Module (PS3.3 Table C.7-13). A count here is
        /// therefore information for that sequence, not a defect in the input.
        public let audioTrackCount: Int
        /// The audio tracks, in file order, with the parameters their sample
        /// entries expose; `audioTracks.count == audioTrackCount`.
        public let audioTracks: [VideoAudioTrack]
    }

    // MARK: - Container Detection

    /// Identifies a container by inspecting its bytes rather than its extension.
    ///
    /// A file's extension is a claim; its bytes are evidence. Endoscopy carts in
    /// particular produce `.mp4`-named files that are really QuickTime.
    public static func detectContainer(_ data: Data) -> VideoContainer {
        // ISO-BMFF: the first box is normally `ftyp`, whose brands decide whether
        // this is MP4 or QuickTime.
        if let ftyp = findBox(type: "ftyp", in: data, range: 0..<data.count) {
            let brands = readBrands(data, box: ftyp)
            if brands.contains(where: { $0.hasPrefix("qt") }) {
                return .quickTime
            }
            // isom, iso2, iso4-6, mp41/42, avc1, dash, and the M4V family are all
            // MP4-compatible brands.
            if brands.contains(where: { brand in
                brand.hasPrefix("iso") || brand.hasPrefix("mp4")
                    || brand == "avc1" || brand == "dash"
                    || brand.hasPrefix("M4V") || brand == "M4A "
            }) {
                return .mp4
            }
            // An ftyp with unfamiliar brands is still ISO-BMFF; treat it as MP4
            // only when it also has a moov box.
            if findBox(type: "moov", in: data, range: 0..<data.count) != nil {
                return .mp4
            }
            return .unknown
        }

        // QuickTime files may omit ftyp entirely and lead with moov or mdat.
        if findBox(type: "moov", in: data, range: 0..<data.count) != nil {
            return .quickTime
        }

        if isTransportStream(data) {
            return .mpegTS
        }

        // MPEG-2 Program Stream / PES (PS3.5 2026a 8.2.5, 8.2.6), then a bare elementary stream.
        if mpeg2SystemsLayer(data) != nil || NALUnit.hasAnnexBStartCode(data) || hasMPEG2StartCode(data) {
            return .elementaryStream
        }

        return .unknown
    }

    /// Whether the data looks like an MPEG-2 Transport Stream.
    ///
    /// A TS is a run of 188-byte packets each beginning with the sync byte 0x47.
    /// Checking several consecutive packets avoids matching a stray 0x47.
    ///
    /// Reference: ISO/IEC 13818-1
    public static func isTransportStream(_ data: Data) -> Bool {
        let packetSize = 188
        let bytes = [UInt8](data.prefix(packetSize * 8))
        guard bytes.count >= packetSize * 2 else { return false }

        // Allow for a leading partial packet by trying each plausible start.
        for start in 0..<min(packetSize, bytes.count) {
            guard bytes[start] == 0x47 else { continue }
            var offset = start
            var matched = 0
            while offset < bytes.count {
                guard bytes[offset] == 0x47 else { break }
                matched += 1
                offset += packetSize
            }
            if matched >= 3 { return true }
        }
        return false
    }

    /// Whether the data begins with an MPEG-2 sequence or pack start code.
    private static func hasMPEG2StartCode(_ data: Data) -> Bool {
        let bytes = [UInt8](data.prefix(4))
        guard bytes.count >= 4 else { return false }
        guard bytes[0] == 0x00, bytes[1] == 0x00, bytes[2] == 0x01 else { return false }
        // B3 sequence header, BA pack header, or a picture start code.
        return bytes[3] == 0xB3 || bytes[3] == 0xBA || bytes[3] == 0x00
    }

    // MARK: - Box Walking

    /// Lists the boxes directly inside a byte range, without descending.
    public static func boxes(in data: Data, range: Range<Int>) -> [Box] {
        var result: [Box] = []
        var offset = range.lowerBound

        while offset + 8 <= range.upperBound {
            guard let size32 = readUInt32(data, at: offset),
                  let type = readFourCC(data, at: offset + 4)
            else { break }

            var size = Int(size32)
            var payloadOffset = offset + 8

            if size == 1 {
                // A 64-bit `largesize` follows the type.
                guard let large = readUInt64(data, at: offset + 8) else { break }
                guard large <= UInt64(Int.max) else { break }
                size = Int(large)
                payloadOffset = offset + 16
            } else if size == 0 {
                // Size 0 means the box runs to the end of the file.
                size = range.upperBound - offset
            }

            guard size >= payloadOffset - offset, offset + size <= range.upperBound else {
                break
            }

            result.append(Box(type: type, offset: offset, size: size, payloadOffset: payloadOffset))
            offset += size
        }

        return result
    }

    /// The end offset of the last complete top-level box, i.e. how many bytes of
    /// `data` the ISO-BMFF structure actually accounts for.
    ///
    /// Returns nil when the bytes are not ISO-BMFF, when a box is malformed or
    /// truncated, or when a box declares size 0 — such a box is defined to run to
    /// the end of the file, so it absorbs any trailing byte and can never
    /// distinguish padding from stream data.
    public static func topLevelBoxExtent(_ data: Data) -> Int? {
        guard let first = readUInt32(data, at: 0), readFourCC(data, at: 4) != nil else {
            return nil
        }
        guard first != 0 else { return nil }

        let parsed = boxes(in: data, range: 0..<data.count)
        guard let last = parsed.last else { return nil }
        // A size-0 box may only appear last; if one did, it already ran to the end.
        guard readUInt32(data, at: last.offset) != 0 else { return nil }
        return last.offset + last.size
    }

    /// Finds the first box of a type directly inside a range.
    public static func findBox(type: String, in data: Data, range: Range<Int>) -> Box? {
        boxes(in: data, range: range).first { $0.type == type }
    }

    /// Follows a path of box types down the tree, e.g. `["moov", "trak", "mdia"]`.
    public static func findBox(path: [String], in data: Data) -> Box? {
        var range = 0..<data.count
        var found: Box?
        for type in path {
            guard let box = findBox(type: type, in: data, range: range) else { return nil }
            found = box
            range = box.payloadOffset..<(box.offset + box.size)
        }
        return found
    }

    // MARK: - File Inspection

    /// Reads an MP4 or MOV file's structure.
    ///
    /// - Returns: The file's structure, or nil when it is not ISO-BMFF at all.
    public static func inspect(_ data: Data) -> FileInfo? {
        let container = detectContainer(data)
        guard container == .mp4 || container == .quickTime else { return nil }

        var brands: [String] = []
        if let ftyp = findBox(type: "ftyp", in: data, range: 0..<data.count) {
            brands = readBrands(data, box: ftyp)
        }

        guard let moov = findBox(type: "moov", in: data, range: 0..<data.count) else {
            return FileInfo(container: container, brands: brands, videoTracks: [],
                            audioTrackCount: 0, audioTracks: [])
        }

        var videoTracks: [TrackInfo] = []
        var audioTracks: [VideoAudioTrack] = []

        let moovRange = moov.payloadOffset..<(moov.offset + moov.size)
        for trak in boxes(in: data, range: moovRange) where trak.type == "trak" {
            let trakRange = trak.payloadOffset..<(trak.offset + trak.size)
            guard let mdia = findBox(type: "mdia", in: data, range: trakRange) else { continue }
            let mdiaRange = mdia.payloadOffset..<(mdia.offset + mdia.size)

            // The handler type says what kind of track this is.
            guard let hdlr = findBox(type: "hdlr", in: data, range: mdiaRange),
                  let handler = readFourCC(data, at: hdlr.payloadOffset + 8)
            else { continue }

            if handler == "soun" {
                audioTracks.append(parseAudioTrack(data, mdiaRange: mdiaRange))
                continue
            }
            guard handler == "vide" else { continue }

            if var track = parseVideoTrack(data, mdiaRange: mdiaRange) {
                track.rotationDegrees = rotationDegrees(data, trakRange: trakRange)
                videoTracks.append(track)
            }
        }

        return FileInfo(
            container: container,
            brands: brands,
            videoTracks: videoTracks,
            audioTrackCount: audioTracks.count,
            audioTracks: audioTracks
        )
    }

    // MARK: - Private

    /// Parses a video track from its `mdia` box.
    private static func parseVideoTrack(_ data: Data, mdiaRange: Range<Int>) -> TrackInfo? {
        // mdhd carries the timescale and duration, which give the frame rate.
        var timescale: UInt32 = 0
        var duration: UInt64 = 0
        if let mdhd = findBox(type: "mdhd", in: data, range: mdiaRange) {
            let versionOffset = mdhd.payloadOffset
            if let version = readUInt8(data, at: versionOffset) {
                if version == 1 {
                    timescale = readUInt32(data, at: versionOffset + 20) ?? 0
                    duration = readUInt64(data, at: versionOffset + 24) ?? 0
                } else {
                    timescale = readUInt32(data, at: versionOffset + 12) ?? 0
                    duration = UInt64(readUInt32(data, at: versionOffset + 16) ?? 0)
                }
            }
        }

        guard let minf = findBox(type: "minf", in: data, range: mdiaRange) else { return nil }
        let minfRange = minf.payloadOffset..<(minf.offset + minf.size)
        guard let stbl = findBox(type: "stbl", in: data, range: minfRange) else { return nil }
        let stblRange = stbl.payloadOffset..<(stbl.offset + stbl.size)

        // stsd holds the sample description: the codec and its parameter sets.
        guard let stsd = findBox(type: "stsd", in: data, range: stblRange) else { return nil }
        // stsd payload: version/flags (4) then entry_count (4), then the entries.
        let entriesStart = stsd.payloadOffset + 8
        let stsdEnd = stsd.offset + stsd.size
        guard entriesStart < stsdEnd else { return nil }

        guard let sampleEntry = boxes(in: data, range: entriesStart..<stsdEnd).first else {
            return nil
        }

        let codec: VideoCodec
        switch sampleEntry.type {
        case "avc1", "avc3", "avc2", "avc4", "mvc1", "mvc2":
            codec = .h264
        case "hvc1", "hev1", "hvc2", "hev2":
            codec = .h265
        case "mp4v", "m2v1", "mpeg", "mp2v":
            codec = .mpeg2
        default:
            codec = .unknown
        }

        // A visual sample entry is 78 bytes before its extension boxes; width and
        // height sit at offsets 24 and 26 within it.
        let width = Int(readUInt16(data, at: sampleEntry.payloadOffset + 24) ?? 0)
        let height = Int(readUInt16(data, at: sampleEntry.payloadOffset + 26) ?? 0)

        let extensionsStart = sampleEntry.payloadOffset + 78
        let sampleEntryEnd = sampleEntry.offset + sampleEntry.size
        var parameterSets: [Data] = []
        var subsetParameterSets: [Data] = []
        var nalLengthSize: Int?
        if extensionsStart < sampleEntryEnd {
            let extensionRange = extensionsStart..<sampleEntryEnd
            // MVC records the dependent view's subset SPS in its own box, beside
            // (or, for an MVC-only entry, instead of) the base view's avcC.
            if let mvcC = findBox(type: "mvcC", in: data, range: extensionRange) {
                subsetParameterSets = parseAVCC(data, box: mvcC)
                nalLengthSize = lengthSize(data, configurationBox: mvcC, offsetOfLengthByte: 4)
            }
            if let avcC = findBox(type: "avcC", in: data, range: extensionRange) {
                parameterSets = parseAVCC(data, box: avcC)
                nalLengthSize = lengthSize(data, configurationBox: avcC, offsetOfLengthByte: 4)
            } else if let hvcC = findBox(type: "hvcC", in: data, range: extensionRange) {
                parameterSets = parseHVCC(data, box: hvcC)
                nalLengthSize = lengthSize(data, configurationBox: hvcC, offsetOfLengthByte: 21)
            } else if !subsetParameterSets.isEmpty {
                parameterSets = subsetParameterSets
            } else if codec == .mpeg2,
                      let esds = findBox(type: "esds", in: data, range: extensionRange),
                      let config = parseESDSDecoderSpecificInfo(data, box: esds) {
                parameterSets = [config]
            }
        }

        // MPEG-2 carries its sequence header in-band, and muxers routinely write
        // an `esds` with no DecoderSpecificInfo at all. Falling back to the first
        // sample keeps such files readable, since the header is required to open
        // the first GOP and so is always present there.
        if parameterSets.isEmpty, codec == .mpeg2,
           let header = firstSampleSequenceHeader(data, stblRange: stblRange) {
            parameterSets = [header]
        }

        // stsz gives the exact sample count — one sample is one coded picture.
        var frameCount = 0
        if let stsz = findBox(type: "stsz", in: data, range: stblRange) {
            frameCount = Int(readUInt32(data, at: stsz.payloadOffset + 8) ?? 0)
        } else if let stz2 = findBox(type: "stz2", in: data, range: stblRange) {
            frameCount = Int(readUInt32(data, at: stz2.payloadOffset + 8) ?? 0)
        }

        var frameRate: Double?
        if timescale > 0, duration > 0, frameCount > 0 {
            let seconds = Double(duration) / Double(timescale)
            if seconds > 0 {
                let rate = Double(frameCount) / seconds
                if rate.isFinite, rate > 0, rate < 1000 { frameRate = rate }
            }
        }

        var track = TrackInfo(
            codec: codec,
            width: width,
            height: height,
            frameCount: frameCount,
            parameterSets: parameterSets,
            frameRate: frameRate
        )
        track.subsetParameterSets = subsetParameterSets
        // The first few pictures are enough: an encoder that packs frames for
        // 3D repeats the arrangement SEI with the first IDR picture.
        if let lengthSize = nalLengthSize, codec == .h264 || codec == .h265 {
            for range in sampleRanges(data, stblRange: stblRange, limit: leadingSampleCount) {
                track.leadingNALUnits += NALUnit.splitLengthPrefixed(
                    data.subdata(in: range), lengthSize: lengthSize)
            }
        }
        return track
    }

    /// How many leading coded pictures are scanned for in-band facts.
    private static let leadingSampleCount = 4

    /// Reads `lengthSizeMinusOne + 1` from an `avcC` / `mvcC` / `hvcC` record.
    private static func lengthSize(_ data: Data, configurationBox box: Box, offsetOfLengthByte: Int) -> Int? {
        guard let byte = readUInt8(data, at: box.payloadOffset + offsetOfLengthByte) else { return nil }
        return Int(byte & 0x03) + 1
    }

    // MARK: - Sample Table

    /// The file ranges of the first `limit` samples of a track.
    ///
    /// Samples are located by walking the sample-to-chunk table against the
    /// chunk offsets and sample sizes, which is the only way ISO-BMFF says
    /// where a sample is. Stops early rather than guessing on a malformed table.
    ///
    /// Reference: ISO/IEC 14496-12 Sections 8.7.3 - 8.7.5
    static func sampleRanges(_ data: Data, stblRange: Range<Int>, limit: Int) -> [Range<Int>] {
        guard limit > 0 else { return [] }

        // Sample sizes: a constant size, or a table of them.
        var sizes: [Int] = []
        var constantSize = 0
        var sampleCount = 0
        if let stsz = findBox(type: "stsz", in: data, range: stblRange) {
            constantSize = Int(readUInt32(data, at: stsz.payloadOffset + 4) ?? 0)
            sampleCount = Int(readUInt32(data, at: stsz.payloadOffset + 8) ?? 0)
            if constantSize == 0 {
                for index in 0..<min(sampleCount, limit) {
                    guard let size = readUInt32(data, at: stsz.payloadOffset + 12 + index * 4) else { break }
                    sizes.append(Int(size))
                }
            }
        }
        func size(of sample: Int) -> Int? {
            if constantSize > 0 { return sample < sampleCount ? constantSize : nil }
            return sample < sizes.count ? sizes[sample] : nil
        }

        // Chunk offsets, 32- or 64-bit.
        var chunkOffsets: [Int] = []
        if let stco = findBox(type: "stco", in: data, range: stblRange) {
            let count = Int(readUInt32(data, at: stco.payloadOffset + 4) ?? 0)
            for index in 0..<min(count, limit) {
                guard let offset = readUInt32(data, at: stco.payloadOffset + 8 + index * 4) else { break }
                chunkOffsets.append(Int(offset))
            }
        } else if let co64 = findBox(type: "co64", in: data, range: stblRange) {
            let count = Int(readUInt32(data, at: co64.payloadOffset + 4) ?? 0)
            for index in 0..<min(count, limit) {
                guard let offset = readUInt64(data, at: co64.payloadOffset + 8 + index * 8),
                      offset <= UInt64(Int.max) else { break }
                chunkOffsets.append(Int(offset))
            }
        }

        // Sample-to-chunk runs: (first_chunk, samples_per_chunk), 1-based chunks.
        var runs: [(firstChunk: Int, samplesPerChunk: Int)] = []
        if let stsc = findBox(type: "stsc", in: data, range: stblRange) {
            let count = Int(readUInt32(data, at: stsc.payloadOffset + 4) ?? 0)
            for index in 0..<min(count, 1024) {
                let entry = stsc.payloadOffset + 8 + index * 12
                guard let first = readUInt32(data, at: entry),
                      let perChunk = readUInt32(data, at: entry + 4) else { break }
                runs.append((Int(first), Int(perChunk)))
            }
        }
        guard !runs.isEmpty else { return [] }

        var ranges: [Range<Int>] = []
        var sample = 0
        for (chunkIndex, chunkOffset) in chunkOffsets.enumerated() {
            let chunkNumber = chunkIndex + 1
            let perChunk = runs.last(where: { $0.firstChunk <= chunkNumber })?.samplesPerChunk ?? 0
            var cursor = chunkOffset
            for _ in 0..<perChunk {
                guard ranges.count < limit, let length = size(of: sample),
                      cursor >= 0, length > 0, cursor + length <= data.count
                else { return ranges }
                ranges.append(cursor..<(cursor + length))
                cursor += length
                sample += 1
            }
            if ranges.count >= limit { break }
        }
        return ranges
    }

    // MARK: - Track Header

    /// The display rotation a track header's matrix requests, in degrees
    /// clockwise, rounded to a quarter turn.
    ///
    /// Reference: ISO/IEC 14496-12 Section 8.3.2 (TrackHeaderBox)
    static func rotationDegrees(_ data: Data, trakRange: Range<Int>) -> Int {
        guard let tkhd = findBox(type: "tkhd", in: data, range: trakRange),
              let version = readUInt8(data, at: tkhd.payloadOffset)
        else { return 0 }
        // version/flags(4), then times and IDs whose width depends on the
        // version, then reserved(8), layer(2), group(2), volume(2), reserved(2).
        let matrixOffset = tkhd.payloadOffset + (version == 1 ? 52 : 40)
        func fixed(_ index: Int) -> Double? {
            guard let raw = readUInt32(data, at: matrixOffset + index * 4) else { return nil }
            return Double(Int32(bitPattern: raw)) / 65536.0
        }
        guard let a = fixed(0), let b = fixed(1) else { return 0 }
        let degrees = atan2(b, a) * 180.0 / .pi
        let quarter = Int((degrees / 90.0).rounded()) * 90
        return ((quarter % 360) + 360) % 360
    }

    /// Extracts SPS and PPS payloads from an `avcC` box.
    ///
    /// The AVCDecoderConfigurationRecord stores parameter sets **without** NAL
    /// headers and length-prefixed, not as Annex B.
    ///
    /// Reference: ISO/IEC 14496-15 Section 5.3.3.1
    public static func parseAVCC(_ data: Data, box: Box) -> [Data] {
        var offset = box.payloadOffset
        let end = box.offset + box.size
        // configurationVersion, AVCProfileIndication, profile_compatibility,
        // AVCLevelIndication, lengthSizeMinusOne, numOfSequenceParameterSets
        guard offset + 6 <= end else { return [] }
        guard let spsCountByte = readUInt8(data, at: offset + 5) else { return [] }
        let spsCount = Int(spsCountByte & 0x1F)
        offset += 6

        var sets: [Data] = []
        for _ in 0..<spsCount {
            guard offset + 2 <= end, let length = readUInt16(data, at: offset) else { break }
            offset += 2
            guard offset + Int(length) <= end else { break }
            sets.append(data.subdata(in: offset..<(offset + Int(length))))
            offset += Int(length)
        }
        return sets
    }

    /// Extracts parameter set payloads from an `hvcC` box.
    ///
    /// The HEVCDecoderConfigurationRecord groups its arrays by NAL type, and each
    /// stored unit **includes** its two-byte NAL header.
    ///
    /// Reference: ISO/IEC 14496-15 Section 8.3.3.1
    public static func parseHVCC(_ data: Data, box: Box) -> [Data] {
        var offset = box.payloadOffset
        let end = box.offset + box.size
        // The fixed portion of the record is 22 bytes, then numOfArrays.
        guard offset + 23 <= end else { return [] }
        guard let arrayCount = readUInt8(data, at: offset + 22) else { return [] }
        offset += 23

        var sets: [Data] = []
        for _ in 0..<Int(arrayCount) {
            guard offset + 3 <= end,
                  let nalCount = readUInt16(data, at: offset + 1)
            else { break }
            offset += 3

            for _ in 0..<Int(nalCount) {
                guard offset + 2 <= end, let length = readUInt16(data, at: offset) else { break }
                offset += 2
                guard offset + Int(length) <= end else { break }
                sets.append(data.subdata(in: offset..<(offset + Int(length))))
                offset += Int(length)
            }
        }
        return sets
    }

    /// Extracts the DecoderSpecificInfo payload from an `esds` box.
    ///
    /// Unlike `avcC` and `hvcC`, an `esds` holds a chain of MPEG-4 descriptors,
    /// each tagged and carrying a variable-length size. For MPEG-2 video the
    /// DecoderSpecificInfo, when present, is the sequence header itself.
    ///
    /// Returns nil when the chain omits a DecoderSpecificInfo, which is common:
    /// MPEG-2 repeats its sequence header in-band, so muxers often store none.
    ///
    /// Reference: ISO/IEC 14496-1 Section 7.2.6 (descriptors),
    /// ISO/IEC 14496-14 Section 5.6 (ESDBox)
    public static func parseESDSDecoderSpecificInfo(_ data: Data, box: Box) -> Data? {
        esDescriptor(data, box: box)?.decoderSpecificInfo
    }

    /// The DecoderConfigDescriptor fields of an `esds` box.
    struct ESDescriptorInfo {
        /// objectTypeIndication (ISO/IEC 14496-1 Table 5, MP4 registration authority).
        let objectTypeIndication: UInt8
        /// maxBitrate in bit/s; 0 when not stated.
        let maxBitrate: UInt32
        /// avgBitrate in bit/s; 0 for variable bit rate or not stated.
        let avgBitrate: UInt32
        /// The DecoderSpecificInfo payload, when present.
        let decoderSpecificInfo: Data?
    }

    /// Reads the DecoderConfigDescriptor of an `esds` box.
    ///
    /// Reference: ISO/IEC 14496-1 Section 7.2.6 (descriptors),
    /// ISO/IEC 14496-14 Section 5.6 (ESDBox)
    static func esDescriptor(_ data: Data, box: Box) -> ESDescriptorInfo? {
        // Payload opens with a version/flags word, then the ES_Descriptor.
        var offset = box.payloadOffset + 4
        let end = box.offset + box.size

        /// Reads one descriptor's tag and size, advancing past its header.
        ///
        /// Sizes use a base-128 encoding of up to four bytes, the high bit of each
        /// marking that another follows.
        func readDescriptorHeader() -> (tag: UInt8, size: Int)? {
            guard let tag = readUInt8(data, at: offset) else { return nil }
            offset += 1
            var size = 0
            for _ in 0..<4 {
                guard let byte = readUInt8(data, at: offset) else { return nil }
                offset += 1
                size = (size << 7) | Int(byte & 0x7F)
                if byte & 0x80 == 0 { break }
            }
            return (tag, size)
        }

        // ES_DescrTag (0x03) wraps the chain.
        guard let esDescriptor = readDescriptorHeader(), esDescriptor.tag == 0x03 else {
            return nil
        }
        // ES_ID (2 bytes) then a flags byte, which can introduce three optional
        // fields that have to be stepped over before the inner descriptors.
        guard let flags = readUInt8(data, at: offset + 2) else { return nil }
        offset += 3
        if flags & 0x80 != 0 { offset += 2 }  // streamDependenceFlag: dependsOn_ES_ID
        if flags & 0x40 != 0 {                // URL_Flag: a length-prefixed URL
            guard let urlLength = readUInt8(data, at: offset) else { return nil }
            offset += 1 + Int(urlLength)
        }
        if flags & 0x20 != 0 { offset += 2 }  // OCRstreamFlag: OCR_ES_Id

        // DecoderConfigDescrTag (0x04) holds the codec identification, then the
        // DecoderSpecificInfo nested inside it.
        guard let decoderConfig = readDescriptorHeader(), decoderConfig.tag == 0x04 else {
            return nil
        }
        // objectTypeIndication (1), streamType/upStream/reserved (1),
        // bufferSizeDB (3), maxBitrate (4), avgBitrate (4).
        guard let objectType = readUInt8(data, at: offset),
              let maxBitrate = readUInt32(data, at: offset + 5),
              let avgBitrate = readUInt32(data, at: offset + 9)
        else { return nil }
        offset += 13

        // Walk the nested descriptors for DecSpecificInfoTag (0x05). Anything else
        // here is skipped by its own size rather than assumed absent.
        var specificInfo: Data?
        while offset < end {
            guard let descriptor = readDescriptorHeader() else { break }
            if descriptor.tag == 0x05 {
                if descriptor.size > 0, offset + descriptor.size <= end {
                    specificInfo = data.subdata(in: offset..<(offset + descriptor.size))
                }
                break
            }
            guard descriptor.size > 0 else { break }
            offset += descriptor.size
        }
        return ESDescriptorInfo(
            objectTypeIndication: objectType, maxBitrate: maxBitrate,
            avgBitrate: avgBitrate, decoderSpecificInfo: specificInfo)
    }

    // MARK: - Audio Tracks

    /// Sample entry codes for linear PCM: QuickTime's and ISO/IEC 23003-5's.
    private static let pcmSampleEntries: [String: Int?] = [
        "lpcm": nil, "sowt": 16, "twos": 16, "in24": 24, "in32": 32,
        "fl32": 32, "fl64": 64, "ipcm": nil, "fpcm": nil, "raw ": 8,
    ]

    /// Reads an audio track's format and parameters from its `mdia` box.
    ///
    /// The AudioSampleEntry (ISO/IEC 14496-12 12.2.3) gives channelcount,
    /// samplesize and samplerate; QuickTime's version 2 sound description moves
    /// them. The codec's own configuration wins where present: the `esds`
    /// objectTypeIndication and AudioSpecificConfig (ISO/IEC 14496-3 1.6.2.1),
    /// `dac3` (ETSI TS 102 366 Annex F), and for MPEG-1/2 audio the first frame
    /// header (ISO/IEC 11172-3 2.4.1.3). Bit rates come from `esds` or `btrt`.
    private static func parseAudioTrack(_ data: Data, mdiaRange: Range<Int>) -> VideoAudioTrack {
        guard let minf = findBox(type: "minf", in: data, range: mdiaRange),
              let stbl = findBox(type: "stbl", in: data,
                                 range: minf.payloadOffset..<(minf.offset + minf.size)),
              case let stblRange = stbl.payloadOffset..<(stbl.offset + stbl.size),
              let stsd = findBox(type: "stsd", in: data, range: stblRange),
              stsd.payloadOffset + 8 < stsd.offset + stsd.size,
              let entry = boxes(in: data, range: (stsd.payloadOffset + 8)..<(stsd.offset + stsd.size)).first
        else { return VideoAudioTrack(format: nil, codecTag: "unknown") }

        let tag = entry.type
        let base = entry.payloadOffset
        let end = entry.offset + entry.size
        func nonZero(_ value: Int?) -> Int? { value.flatMap { $0 > 0 ? $0 : nil } }

        // Sample entry fields. The first reserved word is QuickTime's version.
        var channels: Int?
        var sampleSize: Int?
        var rate: Int?
        var childStarts: [Int]
        if readUInt16(data, at: base + 8) == 2 {
            // QuickTime SoundDescriptionV2: audioSampleRate is a float64 at 32,
            // numAudioChannels at 40, constBitsPerChannel at 48; 64 bytes in all.
            if let bits = readUInt64(data, at: base + 32) {
                let value = Double(bitPattern: bits)
                if value.isFinite, value > 0, value < 1_000_000 { rate = Int(value.rounded()) }
            }
            channels = nonZero(readUInt32(data, at: base + 40).map(Int.init))
            sampleSize = nonZero(readUInt32(data, at: base + 48).map(Int.init))
            childStarts = [base + 64]
        } else {
            channels = nonZero(readUInt16(data, at: base + 16).map(Int.init))
            sampleSize = nonZero(readUInt16(data, at: base + 18).map(Int.init))
            rate = nonZero(readUInt32(data, at: base + 24).map { Int($0 >> 16) })
            // ISO entries have their boxes at 28; QuickTime version 1 adds 16 bytes.
            childStarts = [base + 28, base + 44]
        }
        var children: [Box] = []
        for start in childStarts where start <= end {
            let found = boxes(in: data, range: start..<end)
            if start == end || (found.last.map { $0.offset + $0.size == end } ?? false) {
                children = found
                break
            }
        }
        func child(_ type: String) -> Box? { children.first { $0.type == type } }

        var maxBitRate: Int?
        var avgBitRate: Int?
        if let btrt = child("btrt") {
            maxBitRate = nonZero(readUInt32(data, at: btrt.payloadOffset + 4).map(Int.init))
            avgBitRate = nonZero(readUInt32(data, at: btrt.payloadOffset + 8).map(Int.init))
        }

        var codecTrack: VideoAudioTrack?
        var format: VideoAudioTrack.Format?
        switch tag {
        case "mp4a":
            guard let esds = child("esds"), let info = esDescriptor(data, box: esds) else { break }
            maxBitRate = nonZero(Int(info.maxBitrate)) ?? maxBitRate
            avgBitRate = nonZero(Int(info.avgBitrate)) ?? avgBitRate
            let config = info.decoderSpecificInfo.flatMap(AudioHeaderParser.audioSpecificConfig)
            switch info.objectTypeIndication {
            case 0x40:  // Audio ISO/IEC 14496-3
                if let config {
                    format = config.format
                    let layout = AudioHeaderParser.aacChannels(config.channelConfiguration)
                    codecTrack = VideoAudioTrack(
                        format: format, codecTag: tag,
                        samplingFrequency: config.samplingFrequency,
                        channelCount: layout?.count, hasLFE: layout?.lfe)
                }
            case 0x66, 0x67, 0x68:  // Audio ISO/IEC 13818-7 (MPEG-2 AAC Main, LC, SSR)
                format = .aac
                if let config {
                    let layout = AudioHeaderParser.aacChannels(config.channelConfiguration)
                    codecTrack = VideoAudioTrack(
                        format: .aac, codecTag: tag,
                        samplingFrequency: config.samplingFrequency,
                        channelCount: layout?.count, hasLFE: layout?.lfe)
                }
            case 0x69, 0x6B:  // Audio ISO/IEC 13818-3 / 11172-3: the layer is in the frames
                codecTrack = firstSampleMPEGAudioHeader(data, stblRange: stblRange)?
                    .track(codecTag: tag)
                format = codecTrack?.format
            case 0xA5: format = .ac3
            case 0xA6: format = .eac3
            case 0xA9, 0xAA, 0xAB, 0xAC: format = .dts
            case 0xAD: format = .opus
            default: break
            }
        case ".mp3":
            codecTrack = firstSampleMPEGAudioHeader(data, stblRange: stblRange)?
                .track(codecTag: tag)
            format = codecTrack?.format ?? .mp3
        case "ac-3":
            format = .ac3
            if let dac3 = child("dac3") {
                codecTrack = AudioHeaderParser.dac3(
                    bytes(data, dac3.payloadOffset, 3), codecTag: tag)
            }
        case "ec-3": format = .eac3
        case "Opus": format = .opus
        case "dtsc", "dtsh", "dtsl", "dtse": format = .dts
        case "mlpa": format = .trueHD
        case "alac": format = VideoAudioTrack.Format(rawValue: "ALAC")
        case "samr", "sawb": format = VideoAudioTrack.Format(rawValue: "AMR")
        default:
            if let bits = pcmSampleEntries[tag] {
                format = .lpcm
                if let bits { sampleSize = bits }
                if tag == "ipcm", let pcmC = child("pcmC") {
                    // FullBox header (4), format_flags (1), PCM_sample_size (1).
                    sampleSize = nonZero(readUInt8(data, at: pcmC.payloadOffset + 5).map(Int.init))
                        ?? sampleSize
                }
            }
        }

        var maximum = maxBitRate
        if format == .lpcm, maximum == nil, let rate, let channels, let bits = sampleSize {
            maximum = rate * channels * bits  // PCM's rate follows from its format
        }
        // A compressed format's samplesize is the ISO/IEC 14496-12 template value
        // (16), not the coded stream's depth, which it has none of (D58).
        if let format, VideoAudioTrack.codedWithoutSampleDepth.contains(format) {
            sampleSize = nil
        }
        // "CBR MPEG-1 LAYER III" (PS3.5 8.2.5, 8.2.12): read every sample's frame
        // header, within AudioHeaderParser.maximumScannedFrames.
        if format == .mp3 {
            codecTrack = codecTrack?.with(bitRateScan: mp3BitRateScan(data, stblRange: stblRange))
        }
        return VideoAudioTrack(
            format: format,
            codecTag: tag,
            samplingFrequency: codecTrack?.samplingFrequency ?? rate,
            channelCount: codecTrack?.channelCount ?? channels,
            hasLFE: codecTrack?.hasLFE,
            isDualMono: codecTrack?.isDualMono ?? false,
            bitsPerSample: sampleSize,
            maximumBitRate: codecTrack?.maximumBitRate ?? maximum,
            averageBitRate: avgBitRate,
            frameBitRate: codecTrack?.frameBitRate,
            bitRateScan: codecTrack?.bitRateScan)
    }

    /// Walks the MPEG audio frame header at the start of each sample, in sample
    /// order, up to ``AudioHeaderParser/maximumScannedFrames`` samples. An MP3
    /// sample in MP4 is one frame (ISO/IEC 14496-3 1.6.2.1 object types 32-34;
    /// the `.mp3` QuickTime entry likewise), so the sample table locates every
    /// header without resynchronising.
    private static func mp3BitRateScan(
        _ data: Data, stblRange: Range<Int>
    ) -> VideoAudioTrack.BitRateScan? {
        let limit = AudioHeaderParser.maximumScannedFrames
        guard let samples = sampleLocations(data, stblRange: stblRange, limit: limit) else { return nil }
        var frames: [(header: AudioHeaderParser.MPEGAudioHeader, bytes: ArraySlice<UInt8>)] = []
        for sample in samples.locations {
            // The first 40 bytes hold the header, CRC, side information and any
            // encoder tag ("Xing"/"Info" at 36 at most, "VBRI" at 36).
            let window = bytes(data, sample.offset, min(sample.size, 40))
            guard let header = AudioHeaderParser.mpegAudioHeader(window) else { return nil }
            frames.append((header, window[...]))
        }
        return AudioHeaderParser.bitRateScan(frames, coversWholeStream: samples.isComplete)
    }

    /// Each sample's file offset and size, in order, from `stsz` (ISO/IEC
    /// 14496-12 8.7.3), `stsc` (8.7.4) and `stco`/`co64` (8.7.5), up to `limit`
    /// samples. `isComplete` is false when the limit cut the list short. nil
    /// when a table is missing or inconsistent.
    private static func sampleLocations(
        _ data: Data, stblRange: Range<Int>, limit: Int
    ) -> (locations: [(offset: Int, size: Int)], isComplete: Bool)? {
        guard let stsz = findBox(type: "stsz", in: data, range: stblRange),
              let stsc = findBox(type: "stsc", in: data, range: stblRange),
              let constantSize = readUInt32(data, at: stsz.payloadOffset + 4),
              let sampleCount = readUInt32(data, at: stsz.payloadOffset + 8).map(Int.init),
              let runCount = readUInt32(data, at: stsc.payloadOffset + 4).map(Int.init)
        else { return nil }
        var chunkOffsets: [Int] = []
        if let stco = findBox(type: "stco", in: data, range: stblRange),
           let count = readUInt32(data, at: stco.payloadOffset + 4) {
            for index in 0..<Int(count) {
                guard let value = readUInt32(data, at: stco.payloadOffset + 8 + 4 * index) else { return nil }
                chunkOffsets.append(Int(value))
            }
        } else if let co64 = findBox(type: "co64", in: data, range: stblRange),
                  let count = readUInt32(data, at: co64.payloadOffset + 4) {
            for index in 0..<Int(count) {
                guard let value = readUInt64(data, at: co64.payloadOffset + 8 + 8 * index),
                      value <= UInt64(Int.max) else { return nil }
                chunkOffsets.append(Int(value))
            }
        } else {
            return nil
        }
        // stsc runs: (first_chunk, samples_per_chunk, sample_description_index).
        var runs: [(firstChunk: Int, samplesPerChunk: Int)] = []
        for index in 0..<runCount {
            let base = stsc.payloadOffset + 8 + 12 * index
            guard let first = readUInt32(data, at: base), let perChunk = readUInt32(data, at: base + 4)
            else { return nil }
            runs.append((Int(first), Int(perChunk)))
        }
        let wanted = min(sampleCount, limit)
        var locations: [(offset: Int, size: Int)] = []
        var sampleIndex = 0
        for (chunkIndex, chunkOffset) in chunkOffsets.enumerated() where sampleIndex < wanted {
            let chunkNumber = chunkIndex + 1
            guard let run = runs.last(where: { $0.firstChunk <= chunkNumber }) else { return nil }
            var offset = chunkOffset
            for _ in 0..<run.samplesPerChunk where sampleIndex < wanted {
                let size: Int
                if constantSize != 0 {
                    size = Int(constantSize)
                } else {
                    guard let value = readUInt32(data, at: stsz.payloadOffset + 12 + 4 * sampleIndex)
                    else { return nil }
                    size = Int(value)
                }
                guard offset >= 0, offset < data.count else { return nil }
                locations.append((offset, size))
                offset += size
                sampleIndex += 1
            }
        }
        guard !locations.isEmpty else { return nil }
        return (locations, locations.count == sampleCount)
    }

    /// The MPEG audio frame header at the start of the first sample.
    private static func firstSampleMPEGAudioHeader(
        _ data: Data, stblRange: Range<Int>
    ) -> AudioHeaderParser.MPEGAudioHeader? {
        guard let start = firstChunkOffset(data, stblRange: stblRange) else { return nil }
        let window = bytes(data, start, min(4096, data.count - start))
        return AudioHeaderParser.findMPEGAudioHeader(window, limit: 64)
    }

    /// Up to `count` bytes from a file offset.
    private static func bytes(_ data: Data, _ offset: Int, _ count: Int) -> [UInt8] {
        guard offset >= 0, count > 0, offset < data.count else { return [] }
        let base = data.startIndex + offset
        return [UInt8](data[base..<(base + min(count, data.count - offset))])
    }

    /// The file offset of the first chunk, from `stco` or `co64`.
    private static func firstChunkOffset(_ data: Data, stblRange: Range<Int>) -> Int? {
        // stco holds 32-bit chunk offsets, co64 the 64-bit form; either way the
        // first entry sits past a version/flags word and an entry count.
        var chunkOffset: Int?
        if let stco = findBox(type: "stco", in: data, range: stblRange),
           let value = readUInt32(data, at: stco.payloadOffset + 8) {
            chunkOffset = Int(value)
        } else if let co64 = findBox(type: "co64", in: data, range: stblRange),
                  let value = readUInt64(data, at: co64.payloadOffset + 8),
                  value <= UInt64(Int.max) {
            chunkOffset = Int(value)
        }
        guard let start = chunkOffset, start >= 0, start < data.count else { return nil }
        return start
    }

    /// Recovers an MPEG-2 sequence header from the start of the first sample.
    ///
    /// The sample tables give the first chunk's file offset; a coded MPEG-2 video
    /// sample opens at a start code, and the sequence header precedes the first
    /// picture of a GOP. Scanning a bounded window from there avoids reading the
    /// whole `mdat` while tolerating a leading pack or GOP header.
    private static func firstSampleSequenceHeader(_ data: Data, stblRange: Range<Int>) -> Data? {
        guard let start = firstChunkOffset(data, stblRange: stblRange) else { return nil }

        // A sequence header plus its extensions is well under a kilobyte; the
        // window only has to cover any pack or GOP header sitting ahead of it.
        let window = min(data.count - start, 4096)
        guard window > 4 else { return nil }
        let slice = data.subdata(in: start..<(start + window))

        // Hand back the header and everything after it, so the sequence extension
        // that carries profile, level and chroma format stays readable.
        for index in 0...(slice.count - 4) {
            let base = slice.startIndex + index
            guard slice[base] == 0x00, slice[base + 1] == 0x00,
                  slice[base + 2] == 0x01, slice[base + 3] == 0xB3
            else { continue }
            return slice.subdata(in: (slice.startIndex + index)..<slice.endIndex)
        }
        return nil
    }

    /// Reads the major and compatible brands from an `ftyp` box.
    private static func readBrands(_ data: Data, box: Box) -> [String] {
        var brands: [String] = []
        if let major = readFourCC(data, at: box.payloadOffset) {
            brands.append(major)
        }
        // major_brand (4) + minor_version (4), then compatible brands.
        var offset = box.payloadOffset + 8
        let end = box.offset + box.size
        while offset + 4 <= end {
            if let brand = readFourCC(data, at: offset) {
                brands.append(brand)
            }
            offset += 4
        }
        return brands
    }

    // MARK: - Byte Readers

    private static func readUInt8(_ data: Data, at offset: Int) -> UInt8? {
        guard offset >= 0, offset < data.count else { return nil }
        return data[data.startIndex + offset]
    }

    private static func readUInt16(_ data: Data, at offset: Int) -> UInt16? {
        guard offset >= 0, offset + 2 <= data.count else { return nil }
        let base = data.startIndex + offset
        return (UInt16(data[base]) << 8) | UInt16(data[base + 1])
    }

    private static func readUInt32(_ data: Data, at offset: Int) -> UInt32? {
        guard offset >= 0, offset + 4 <= data.count else { return nil }
        let base = data.startIndex + offset
        return (UInt32(data[base]) << 24) | (UInt32(data[base + 1]) << 16)
            | (UInt32(data[base + 2]) << 8) | UInt32(data[base + 3])
    }

    private static func readUInt64(_ data: Data, at offset: Int) -> UInt64? {
        guard offset >= 0, offset + 8 <= data.count else { return nil }
        let base = data.startIndex + offset
        var value: UInt64 = 0
        for index in 0..<8 {
            value = (value << 8) | UInt64(data[base + index])
        }
        return value
    }

    private static func readFourCC(_ data: Data, at offset: Int) -> String? {
        guard offset >= 0, offset + 4 <= data.count else { return nil }
        let base = data.startIndex + offset
        let bytes = [data[base], data[base + 1], data[base + 2], data[base + 3]]
        // Box types are printable ASCII; anything else means we are misaligned.
        guard bytes.allSatisfy({ $0 >= 0x20 && $0 <= 0x7E }) else { return nil }
        return String(bytes: bytes, encoding: .ascii)
    }
}
