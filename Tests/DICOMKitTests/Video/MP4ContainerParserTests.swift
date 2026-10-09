//
// MP4ContainerParserTests.swift
// DICOMKit
//
// Copyright © 2026 DICOMKit. All rights reserved.
//

import XCTest
@testable import DICOMKit

/// ISO-BMFF box walking, container detection and parameter-set recovery.
///
/// The fixtures are assembled here from the box layouts in the specifications
/// rather than captured from an encoder, so the expected values follow from the
/// standard. Building them programmatically also keeps the test readable, since a
/// real MP4's sample tables run to kilobytes of little interest.
///
/// Reference: ISO/IEC 14496-12 (ISO-BMFF), 14496-14 (MP4), 14496-15 (AVC/HEVC)
final class MP4ContainerParserTests: XCTestCase {

    // MARK: - Fixture Construction

    /// Wraps a payload in a box header.
    private func box(_ type: String, _ payload: Data) -> Data {
        var data = Data()
        data.append(uint32: UInt32(payload.count + 8))
        data.append(contentsOf: Array(type.utf8))
        data.append(payload)
        return data
    }

    private func ftyp(major: String = "isom",
                      compatible: [String] = ["isom", "mp41", "avc1"]) -> Data {
        var payload = Data(major.utf8)
        payload.append(uint32: 512)
        for brand in compatible { payload.append(contentsOf: Array(brand.utf8)) }
        return box("ftyp", payload)
    }

    private func mdhd(timescale: UInt32, duration: UInt32) -> Data {
        var payload = Data()
        payload.append(uint32: 0)            // version 0 + flags
        payload.append(uint32: 0)            // creation_time
        payload.append(uint32: 0)            // modification_time
        payload.append(uint32: timescale)
        payload.append(uint32: duration)
        payload.append(uint16: 0x55C4)       // language
        payload.append(uint16: 0)            // pre_defined
        return box("mdhd", payload)
    }

    private func hdlr(handler: String) -> Data {
        var payload = Data()
        payload.append(uint32: 0)            // version + flags
        payload.append(uint32: 0)            // pre_defined
        payload.append(contentsOf: Array(handler.utf8))
        payload.append(Data(repeating: 0, count: 12))
        payload.append(contentsOf: Array("Handler\0".utf8))
        return box("hdlr", payload)
    }

    /// An AVCDecoderConfigurationRecord. Parameter sets are stored length-prefixed
    /// and **with** their NAL headers (ISO/IEC 14496-15 5.3.3.1).
    private func avcC(sps: [Data], pps: [Data]) -> Data {
        var payload = Data([0x01, 0x64, 0x00, 0x29, 0xFF])
        payload.append(UInt8(0xE0 | sps.count))
        for set in sps {
            payload.append(uint16: UInt16(set.count))
            payload.append(set)
        }
        payload.append(UInt8(pps.count))
        for set in pps {
            payload.append(uint16: UInt16(set.count))
            payload.append(set)
        }
        return box("avcC", payload)
    }

    /// An HEVCDecoderConfigurationRecord. Its fixed portion is 22 bytes and each
    /// stored unit **includes** its two-byte NAL header (ISO/IEC 14496-15 8.3.3.1).
    private func hvcC(arrays: [(nalType: UInt8, units: [Data])]) -> Data {
        var payload = Data()
        payload.append(0x01)                 // configurationVersion
        payload.append(0x01)                 // profile_space/tier/profile_idc
        payload.append(uint32: 0x6000_0000)  // profile_compatibility_flags
        payload.append(Data(repeating: 0, count: 6))  // constraint flags
        payload.append(120)                  // general_level_idc
        payload.append(uint16: 0xF000)       // min_spatial_segmentation_idc
        payload.append(0xFC)                 // parallelismType
        payload.append(0xFD)                 // chromaFormat
        payload.append(0xF8)                 // bitDepthLumaMinus8
        payload.append(0xF8)                 // bitDepthChromaMinus8
        payload.append(uint16: 0)            // avgFrameRate
        payload.append(0x0F)                 // constantFrameRate etc
        XCTAssertEqual(payload.count, 22, "hvcC fixed portion is 22 bytes")

        payload.append(UInt8(arrays.count))
        for array in arrays {
            payload.append(0x80 | array.nalType)
            payload.append(uint16: UInt16(array.units.count))
            for unit in array.units {
                payload.append(uint16: UInt16(unit.count))
                payload.append(unit)
            }
        }
        return box("hvcC", payload)
    }

    /// A VisualSampleEntry: 78 bytes of payload before its extension boxes.
    private func visualSampleEntry(
        format: String, width: UInt16, height: UInt16, extensions: Data
    ) -> Data {
        var payload = Data(repeating: 0, count: 6)   // reserved
        payload.append(uint16: 1)                    // data_reference_index
        payload.append(uint16: 0)                    // pre_defined
        payload.append(uint16: 0)                    // reserved
        payload.append(Data(repeating: 0, count: 12))// pre_defined
        payload.append(uint16: width)
        payload.append(uint16: height)
        payload.append(uint32: 0x0048_0000)          // horizresolution 72 dpi
        payload.append(uint32: 0x0048_0000)          // vertresolution
        payload.append(uint32: 0)                    // reserved
        payload.append(uint16: 1)                    // frame_count
        payload.append(Data(repeating: 0, count: 32))// compressorname
        payload.append(uint16: 24)                   // depth
        payload.append(uint16: 0xFFFF)               // pre_defined -1
        XCTAssertEqual(payload.count, 78, "VisualSampleEntry payload is 78 bytes")
        payload.append(extensions)
        return box(format, payload)
    }

    private func stsz(sampleCount: UInt32) -> Data {
        var payload = Data()
        payload.append(uint32: 0)            // version + flags
        payload.append(uint32: 1000)         // sample_size, uniform
        payload.append(uint32: sampleCount)
        return box("stsz", payload)
    }

    private func videoTrack(
        sampleEntry: Data,
        frameCount: UInt32,
        timescale: UInt32 = 30000,
        duration: UInt32,
        handler: String = "vide"
    ) -> Data {
        let stbl = box("stbl", stsd(sampleEntry) + stsz(sampleCount: frameCount))
        let minf = box("minf", stbl)
        let mdia = box("mdia", mdhd(timescale: timescale, duration: duration)
                       + hdlr(handler: handler) + minf)
        return box("trak", mdia)
    }

    private func stsd(_ entry: Data) -> Data {
        var payload = Data()
        payload.append(uint32: 0)            // version + flags
        payload.append(uint32: 1)            // entry_count
        payload.append(entry)
        return box("stsd", payload)
    }

    private func mp4File(tracks: [Data], major: String = "isom",
                         compatible: [String] = ["isom", "mp41", "avc1"]) -> Data {
        var moovPayload = Data()
        for track in tracks { moovPayload.append(track) }
        return ftyp(major: major, compatible: compatible)
            + box("moov", moovPayload)
            + box("mdat", Data(repeating: 0xAB, count: 64))
    }

    // MARK: - Parameter Sets

    /// The 1080p High@4.1 SPS from H264ParserTests, with its 0x67 NAL header,
    /// which is how avcC stores it: ISO/IEC 14496-15 keeps whole NAL units.
    private static let spsH264Unit = Data([
        0x67,
        0x64, 0x00, 0x29, 0xAC, 0xB4, 0x03, 0xC0, 0x11, 0x3F, 0x2C, 0x20,
        0x00, 0x00, 0x03, 0x00, 0x20, 0x00, 0x00, 0x07, 0x98,
    ])

    /// The Main@4.0 HEVC SPS from HEVCParserTests, with its NAL header, which is
    /// how hvcC stores it.
    private static let spsHEVCUnit = Data([
        0x42, 0x01, 0x01, 0x01, 0x40, 0x00, 0x00, 0x03, 0x00, 0x80, 0x00, 0x00,
        0x03, 0x00, 0x00, 0x03, 0x00, 0x78, 0xA0, 0x03, 0xC0, 0x80, 0x10, 0xE5,
        0x96, 0xB9, 0x24, 0xCA, 0xE0, 0x10, 0x00, 0x00, 0x03, 0x00, 0x10, 0x00,
        0x00, 0x03, 0x01, 0xE1,
    ])

    private func h264MP4(frameCount: UInt32 = 300, durationSeconds: Double = 10.0) -> Data {
        let entry = visualSampleEntry(
            format: "avc1", width: 1920, height: 1080,
            extensions: avcC(sps: [Self.spsH264Unit], pps: [Data([0xEE, 0x3C, 0xB0])])
        )
        return mp4File(tracks: [videoTrack(
            sampleEntry: entry, frameCount: frameCount,
            duration: UInt32(30000.0 * durationSeconds)
        )])
    }

    private func hevcMP4(frameCount: UInt32 = 120) -> Data {
        let entry = visualSampleEntry(
            format: "hvc1", width: 1920, height: 1080,
            extensions: hvcC(arrays: [(nalType: 33, units: [Self.spsHEVCUnit])])
        )
        return mp4File(tracks: [videoTrack(
            sampleEntry: entry, frameCount: frameCount, duration: 30000 * 4
        )])
    }

    // MARK: - Container Detection

    func test_detectContainer_recognizesMP4ByBrand() {
        XCTAssertEqual(MP4ContainerParser.detectContainer(h264MP4()), .mp4)
    }

    func test_detectContainer_recognizesQuickTimeByBrand() {
        // A .mov is structurally ISO-BMFF but is not an MP4 brand, so it must be
        // remuxed rather than passed through.
        let mov = mp4File(tracks: [videoTrack(
            sampleEntry: visualSampleEntry(format: "avc1", width: 1920, height: 1080,
                                          extensions: avcC(sps: [Self.spsH264Unit], pps: [])),
            frameCount: 300, duration: 300000
        )], major: "qt  ", compatible: ["qt  "])

        XCTAssertEqual(MP4ContainerParser.detectContainer(mov), .quickTime)
    }

    func test_detectContainer_isDrivenByBytesNotExtension() {
        // The point of sniffing: a file named .mp4 that is really QuickTime must
        // still be identified as QuickTime.
        let mov = mp4File(tracks: [], major: "qt  ", compatible: ["qt  "])
        XCTAssertEqual(MP4ContainerParser.detectContainer(mov), .quickTime)
        XCTAssertFalse(MP4ContainerParser.detectContainer(mov).isPermittedByDICOM(for: .h264))
    }

    func test_detectContainer_recognizesTransportStream() {
        // 188-byte packets each starting with the 0x47 sync byte.
        var ts = Data()
        for index in 0..<8 {
            ts.append(0x47)
            ts.append(Data(repeating: UInt8(index), count: 187))
        }
        XCTAssertEqual(MP4ContainerParser.detectContainer(ts), .mpegTS)
        XCTAssertTrue(MP4ContainerParser.isTransportStream(ts))
    }

    func test_isTransportStream_rejectsStray0x47() {
        // A single 0x47 in unrelated data is not a transport stream.
        var data = Data(repeating: 0x00, count: 512)
        data[10] = 0x47
        XCTAssertFalse(MP4ContainerParser.isTransportStream(data))
        XCTAssertFalse(MP4ContainerParser.isTransportStream(Data()))
    }

    func test_detectContainer_recognizesAnnexBElementaryStream() {
        let annexB = Data([0x00, 0x00, 0x00, 0x01, 0x67, 0x64, 0x00, 0x29])
        XCTAssertEqual(MP4ContainerParser.detectContainer(annexB), .elementaryStream)
    }

    func test_detectContainer_recognizesMPEG2ElementaryStream() {
        let mpeg2 = Data([0x00, 0x00, 0x01, 0xB3, 0x2D, 0x02, 0x40, 0x33])
        XCTAssertEqual(MP4ContainerParser.detectContainer(mpeg2), .elementaryStream)
    }

    func test_detectContainer_unknownForArbitraryBytes() {
        XCTAssertEqual(MP4ContainerParser.detectContainer(Data([0x89, 0x50, 0x4E, 0x47])), .unknown)
        XCTAssertEqual(MP4ContainerParser.detectContainer(Data()), .unknown)
    }

    func test_permittedContainers_matchTheStandard() {
        // PS3.5 2026a 8.2.7-8.2.11 (H.264, HEVC): MPEG-TS or MP4 only.
        for codec in [VideoCodec.h264, .h265, .unknown] {
            XCTAssertTrue(VideoContainer.mp4.isPermittedByDICOM(for: codec))
            XCTAssertTrue(VideoContainer.mpegTS.isPermittedByDICOM(for: codec))
            XCTAssertFalse(VideoContainer.quickTime.isPermittedByDICOM(for: codec))
            XCTAssertFalse(VideoContainer.elementaryStream.isPermittedByDICOM(for: codec))
            XCTAssertFalse(VideoContainer.unknown.isPermittedByDICOM(for: codec))
        }
        // PS3.5 2026a 8.2.5 / 8.2.6 (MPEG-2): "The container format for the video bit
        // stream is not constrained" — MPEG-TS, MPEG-PS, MPEG-ES, MPEG-PES or MP4.
        XCTAssertTrue(VideoContainer.mp4.isPermittedByDICOM(for: .mpeg2))
        XCTAssertTrue(VideoContainer.mpegTS.isPermittedByDICOM(for: .mpeg2))
        XCTAssertTrue(VideoContainer.elementaryStream.isPermittedByDICOM(for: .mpeg2))
        XCTAssertTrue(VideoContainer.quickTime.isPermittedByDICOM(for: .mpeg2))
        XCTAssertFalse(VideoContainer.unknown.isPermittedByDICOM(for: .mpeg2))
    }

    // MARK: - Box Walking

    func test_boxes_listsTopLevelBoxesInOrder() {
        let file = h264MP4()
        let types = MP4ContainerParser.boxes(in: file, range: 0..<file.count).map(\.type)
        XCTAssertEqual(types, ["ftyp", "moov", "mdat"])
    }

    func test_findBox_followsAPath() throws {
        let file = h264MP4()
        let stsd = try XCTUnwrap(MP4ContainerParser.findBox(
            path: ["moov", "trak", "mdia", "minf", "stbl", "stsd"], in: file))
        XCTAssertEqual(stsd.type, "stsd")
        XCTAssertGreaterThan(stsd.payloadSize, 0)
    }

    func test_findBox_returnsNilForAbsentPath() {
        let file = h264MP4()
        XCTAssertNil(MP4ContainerParser.findBox(path: ["moov", "nope"], in: file))
        XCTAssertNil(MP4ContainerParser.findBox(path: ["zzzz"], in: file))
    }

    func test_boxes_handlesSixtyFourBitLargeSize() {
        // size == 1 means a 64-bit largesize follows the type.
        var data = Data()
        data.append(uint32: 1)
        data.append(contentsOf: Array("mdat".utf8))
        data.append(uint64: 32)
        data.append(Data(repeating: 0xCD, count: 16))

        let parsed = MP4ContainerParser.boxes(in: data, range: 0..<data.count)
        XCTAssertEqual(parsed.count, 1)
        XCTAssertEqual(parsed[0].type, "mdat")
        XCTAssertEqual(parsed[0].size, 32)
        XCTAssertEqual(parsed[0].payloadOffset, 16, "header is 16 bytes with largesize")
    }

    func test_boxes_handlesSizeZeroMeaningToEndOfFile() {
        var data = Data()
        data.append(uint32: 0)
        data.append(contentsOf: Array("mdat".utf8))
        data.append(Data(repeating: 0xEF, count: 20))

        let parsed = MP4ContainerParser.boxes(in: data, range: 0..<data.count)
        XCTAssertEqual(parsed.count, 1)
        XCTAssertEqual(parsed[0].size, 28, "size 0 runs to the end of the file")
    }

    func test_boxes_stopsAtImplausibleSize() {
        // A box claiming to be larger than the buffer must not be reported.
        var data = Data()
        data.append(uint32: 0xFFFF_FFF0)
        data.append(contentsOf: Array("mdat".utf8))
        data.append(Data(repeating: 0, count: 8))
        XCTAssertTrue(MP4ContainerParser.boxes(in: data, range: 0..<data.count).isEmpty)
    }

    func test_boxes_stopsAtNonPrintableType() {
        // A misaligned read yields non-ASCII "types"; stopping beats inventing boxes.
        var data = Data()
        data.append(uint32: 16)
        data.append(contentsOf: [0x00, 0x01, 0x02, 0x03])
        data.append(Data(repeating: 0, count: 8))
        XCTAssertTrue(MP4ContainerParser.boxes(in: data, range: 0..<data.count).isEmpty)
    }

    // MARK: - Track Inspection

    func test_inspect_readsH264TrackGeometryAndFrameCount() throws {
        let info = try XCTUnwrap(MP4ContainerParser.inspect(h264MP4(frameCount: 300)))

        XCTAssertEqual(info.container, .mp4)
        XCTAssertEqual(info.videoTracks.count, 1)
        XCTAssertEqual(info.audioTrackCount, 0)

        let track = try XCTUnwrap(info.videoTracks.first)
        XCTAssertEqual(track.codec, .h264)
        XCTAssertEqual(track.width, 1920)
        XCTAssertEqual(track.height, 1080)
        XCTAssertEqual(track.frameCount, 300,
                       "the sample table gives the exact count, no bitstream walk")
    }

    func test_inspect_readsHEVCTrack() throws {
        let info = try XCTUnwrap(MP4ContainerParser.inspect(hevcMP4(frameCount: 120)))
        let track = try XCTUnwrap(info.videoTracks.first)
        XCTAssertEqual(track.codec, .h265)
        XCTAssertEqual(track.frameCount, 120)
    }

    func test_inspect_derivesFrameRateFromTimescaleAndDuration() throws {
        // 300 samples over 10 seconds is 30 fps.
        let info = try XCTUnwrap(MP4ContainerParser.inspect(
            h264MP4(frameCount: 300, durationSeconds: 10.0)))
        let rate = try XCTUnwrap(info.videoTracks.first?.frameRate)
        XCTAssertEqual(rate, 30.0, accuracy: 0.01)
    }

    func test_inspect_countsAudioTracks() throws {
        // DICOM video may carry audio (PS3.5 8.2.5-8.2.12, Table 8.2.12-1); the
        // count drives the "kept, not checked" warning and (003A,0300).
        let videoEntry = visualSampleEntry(
            format: "avc1", width: 1920, height: 1080,
            extensions: avcC(sps: [Self.spsH264Unit], pps: []))
        let audioEntry = visualSampleEntry(
            format: "mp4a", width: 0, height: 0, extensions: Data())

        let file = mp4File(tracks: [
            videoTrack(sampleEntry: videoEntry, frameCount: 300, duration: 300000),
            videoTrack(sampleEntry: audioEntry, frameCount: 500,
                       timescale: 44100, duration: 441000, handler: "soun"),
        ])

        let info = try XCTUnwrap(MP4ContainerParser.inspect(file))
        XCTAssertEqual(info.videoTracks.count, 1)
        XCTAssertEqual(info.audioTrackCount, 1)
    }

    func test_inspect_reportsEveryVideoTrack() throws {
        // Multiple video tracks must be visible so the caller can reject rather
        // than silently picking track 0.
        let entry = visualSampleEntry(
            format: "avc1", width: 1920, height: 1080,
            extensions: avcC(sps: [Self.spsH264Unit], pps: []))
        let file = mp4File(tracks: [
            videoTrack(sampleEntry: entry, frameCount: 300, duration: 300000),
            videoTrack(sampleEntry: entry, frameCount: 300, duration: 300000),
        ])

        let info = try XCTUnwrap(MP4ContainerParser.inspect(file))
        XCTAssertEqual(info.videoTracks.count, 2)
    }

    func test_inspect_returnsNilForNonISOBMFF() {
        XCTAssertNil(MP4ContainerParser.inspect(Data([0x47, 0x00, 0x00, 0x00])))
        XCTAssertNil(MP4ContainerParser.inspect(Data()))
    }

    func test_inspect_readsBrands() throws {
        let info = try XCTUnwrap(MP4ContainerParser.inspect(h264MP4()))
        XCTAssertEqual(info.brands.first, "isom", "the major brand comes first")
        XCTAssertTrue(info.brands.contains("mp41"))
        XCTAssertTrue(info.brands.contains("avc1"))
    }

    // MARK: - Parameter Set Recovery

    func test_avcC_parameterSetsFeedTheSPSParser() throws {
        // This is the point of the whole exercise: probe an MP4's profile, level
        // and geometry without converting the bit stream to Annex B.
        let info = try XCTUnwrap(MP4ContainerParser.inspect(h264MP4()))
        let track = try XCTUnwrap(info.videoTracks.first)
        XCTAssertEqual(track.parameterSets.count, 1)

        let payload = try XCTUnwrap(track.parameterSets.first)
        XCTAssertEqual(payload, Self.spsH264Unit,
                       "avcC stores the SPS as a whole NAL unit, header included")

        let sps = try XCTUnwrap(H264Parser.parseSPS(nalUnit: payload))
        XCTAssertEqual(sps.width, 1920)
        XCTAssertEqual(sps.height, 1080, "frame cropping applied, not 1088")
        XCTAssertEqual(sps.profileIDC, 100)
        XCTAssertEqual(sps.levelIDC, 41)
    }

    func test_hvcC_parameterSetsFeedTheHEVCParser() throws {
        let info = try XCTUnwrap(MP4ContainerParser.inspect(hevcMP4()))
        let track = try XCTUnwrap(info.videoTracks.first)

        let unit = try XCTUnwrap(track.parameterSets.first)
        XCTAssertEqual(unit, Self.spsHEVCUnit, "hvcC keeps the two-byte NAL header")

        // The stored unit still carries its NAL header, so the header-aware entry
        // point is the right one.
        let sps = try XCTUnwrap(HEVCParser.parseSPS(nalUnit: unit))
        XCTAssertEqual(sps.width, 1920)
        XCTAssertEqual(sps.height, 1080)
        XCTAssertEqual(sps.profileIDC, 1)
    }

    func test_avcC_handlesMultipleParameterSets() throws {
        let secondSPS = Data([0x67, 0x64, 0x00, 0x1F, 0xAC, 0xB4, 0x02, 0x80, 0x2D, 0xD0, 0x80])
        let entry = visualSampleEntry(
            format: "avc1", width: 1280, height: 720,
            extensions: avcC(sps: [Self.spsH264Unit, secondSPS],
                             pps: [Data([0xEE, 0x3C, 0xB0])]))
        let file = mp4File(tracks: [videoTrack(
            sampleEntry: entry, frameCount: 100, duration: 100000)])

        let info = try XCTUnwrap(MP4ContainerParser.inspect(file))
        let track = try XCTUnwrap(info.videoTracks.first)
        XCTAssertEqual(track.parameterSets.count, 2)
        XCTAssertEqual(track.parameterSets[1], secondSPS)
    }

    // MARK: - Malformed input

    func test_truncatedFile_doesNotCrash() {
        let file = h264MP4()
        for length in stride(from: 1, to: file.count, by: 7) {
            _ = MP4ContainerParser.inspect(file.prefix(length))
            _ = MP4ContainerParser.detectContainer(file.prefix(length))
        }
    }

    func test_randomBytes_doNotCrash() {
        var generator = SystemRandomNumberGenerator()
        for _ in 0..<100 {
            var bytes = Data()
            for _ in 0..<128 { bytes.append(UInt8.random(in: 0...255, using: &generator)) }
            _ = MP4ContainerParser.inspect(bytes)
            _ = MP4ContainerParser.detectContainer(bytes)
        }
    }

    func test_corruptedBoxSizes_doNotCrash() {
        var file = h264MP4()
        // Corrupt the moov box size and confirm the walk terminates.
        if file.count > 40 {
            file[28] = 0xFF
            file[29] = 0xFF
        }
        _ = MP4ContainerParser.inspect(file)
    }
}

// MARK: - Big-Endian Append Helpers

/// Shared with the other video test files, which build the same ISO-BMFF boxes.
extension Data {
    mutating func append(uint16 value: UInt16) {
        append(UInt8(truncatingIfNeeded: value >> 8))
        append(UInt8(truncatingIfNeeded: value))
    }

    mutating func append(uint32 value: UInt32) {
        append(UInt8(truncatingIfNeeded: value >> 24))
        append(UInt8(truncatingIfNeeded: value >> 16))
        append(UInt8(truncatingIfNeeded: value >> 8))
        append(UInt8(truncatingIfNeeded: value))
    }

    mutating func append(uint64 value: UInt64) {
        for shift in stride(from: 56, through: 0, by: -8) {
            append(UInt8(truncatingIfNeeded: value >> UInt64(shift)))
        }
    }
}
