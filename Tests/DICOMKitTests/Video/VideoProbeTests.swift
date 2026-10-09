//
// VideoProbeTests.swift
// DICOMKit
//
// Copyright © 2026 DICOMKit. All rights reserved.
//

import XCTest
@testable import DICOMKit
@testable import DICOMCore

/// End-to-end probing: container detection, parameter-set recovery, frame
/// counting, and the guards that redirect non-video input elsewhere.
final class VideoProbeTests: XCTestCase {

    // MARK: - Fixtures

    /// A 1080p High@4.1 SPS NAL unit, cropped to 1080 and carrying VUI timing.
    private static let spsH264NAL: [UInt8] = [
        0x67, 0x64, 0x00, 0x29, 0xAC, 0xB4, 0x03, 0xC0, 0x11, 0x3F, 0x2C, 0x20,
        0x00, 0x00, 0x03, 0x00, 0x20, 0x00, 0x00, 0x07, 0x98,
    ]

    /// A Baseline SPS, which no DICOM transfer syntax accepts.
    private static let spsBaselineNAL: [UInt8] = [
        0x67, 0x42, 0x00, 0x1E, 0xDA, 0x02, 0x80, 0xF6, 0x40,
    ]

    /// An HEVC Main@4.0 SPS NAL unit.
    private static let spsHEVCNAL: [UInt8] = [
        0x42, 0x01, 0x01, 0x01, 0x40, 0x00, 0x00, 0x03, 0x00, 0x80, 0x00, 0x00,
        0x03, 0x00, 0x00, 0x03, 0x00, 0x78, 0xA0, 0x03, 0xC0, 0x80, 0x10, 0xE5,
        0x96, 0xB9, 0x24, 0xCA, 0xE0, 0x10, 0x00, 0x00, 0x03, 0x00, 0x10, 0x00,
        0x00, 0x03, 0x01, 0xE1,
    ]

    /// An MPEG-2 MP@ML sequence header, 720x576 at 25 fps.
    private static let mpeg2SequenceHeader: [UInt8] = [
        0x00, 0x00, 0x01, 0xB3, 0x2D, 0x02, 0x40, 0x33, 0x13, 0x88, 0x23, 0x80,
        0x80, 0x00, 0x00, 0x01, 0xB5, 0x14, 0x8A, 0x00, 0x01, 0x00, 0x00, 0x80,
    ]

    /// An Annex B H.264 elementary stream with the given number of coded pictures.
    private func h264ElementaryStream(frames: Int, sps: [UInt8]? = nil) -> Data {
        var stream = Data([0x00, 0x00, 0x00, 0x01])
        stream.append(contentsOf: sps ?? Self.spsH264NAL)
        stream.append(contentsOf: [0x00, 0x00, 0x00, 0x01, 0x68, 0xEE, 0x3C, 0x80])
        for index in 0..<frames {
            // first_mb_in_slice == 0 starts a picture: ue(v) 0 is the bit 1.
            let nalType: UInt8 = index == 0 ? 0x65 : 0x41
            stream.append(contentsOf: [0x00, 0x00, 0x00, 0x01, nalType, 0x88, 0x84, 0x00])
        }
        return stream
    }

    private func hevcElementaryStream(frames: Int) -> Data {
        var stream = Data([0x00, 0x00, 0x00, 0x01])
        stream.append(contentsOf: Self.spsHEVCNAL)
        for _ in 0..<frames {
            stream.append(contentsOf: [0x00, 0x00, 0x00, 0x01, 0x26, 0x01, 0xAF, 0x00])
        }
        return stream
    }

    private func mpeg2ElementaryStream(frames: Int) -> Data {
        var stream = Data(Self.mpeg2SequenceHeader)
        for _ in 0..<frames {
            stream.append(contentsOf: [0x00, 0x00, 0x01, 0x00, 0x00, 0x0F, 0xFF, 0xF8])
        }
        return stream
    }

    /// A minimal MP4 carrying one H.264 track, with the SPS in an `avcC` box the
    /// way a camera writes it: length-prefixed, NAL header included.
    private func h264MP4(sps: [UInt8], frames: UInt32) -> Data {
        func box(_ type: String, _ payload: Data) -> Data {
            var data = Data()
            data.append(uint32: UInt32(payload.count + 8))
            data.append(contentsOf: Array(type.utf8))
            data.append(payload)
            return data
        }

        var avcCPayload = Data([0x01, 0x64, 0x00, 0x29, 0xFF, 0xE1])
        avcCPayload.append(uint16: UInt16(sps.count))
        avcCPayload.append(contentsOf: sps)
        avcCPayload.append(0x00)  // numOfPictureParameterSets
        let avcC = box("avcC", avcCPayload)

        var entry = Data(repeating: 0, count: 6)      // reserved
        entry.append(uint16: 1)                       // data_reference_index
        entry.append(uint16: 0)                       // pre_defined
        entry.append(uint16: 0)                       // reserved
        entry.append(Data(repeating: 0, count: 12))   // pre_defined
        entry.append(uint16: 1920)
        entry.append(uint16: 1080)
        entry.append(uint32: 0x0048_0000)             // horizresolution
        entry.append(uint32: 0x0048_0000)             // vertresolution
        entry.append(uint32: 0)                       // reserved
        entry.append(uint16: 1)                       // frame_count
        entry.append(Data(repeating: 0, count: 32))   // compressorname
        entry.append(uint16: 24)                      // depth
        entry.append(uint16: 0xFFFF)                  // pre_defined -1
        entry.append(avcC)
        let avc1 = box("avc1", entry)

        var stsdPayload = Data()
        stsdPayload.append(uint32: 0)                 // version + flags
        stsdPayload.append(uint32: 1)                 // entry_count
        stsdPayload.append(avc1)

        var stszPayload = Data()
        stszPayload.append(uint32: 0)                 // version + flags
        stszPayload.append(uint32: 1000)              // uniform sample_size
        stszPayload.append(uint32: frames)

        let stbl = box("stbl", box("stsd", stsdPayload) + box("stsz", stszPayload))

        var mdhdPayload = Data()
        mdhdPayload.append(uint32: 0)                 // version + flags
        mdhdPayload.append(uint32: 0)                 // creation_time
        mdhdPayload.append(uint32: 0)                 // modification_time
        mdhdPayload.append(uint32: 30000)             // timescale
        mdhdPayload.append(uint32: frames * 1000)     // duration
        mdhdPayload.append(uint16: 0x55C4)            // language
        mdhdPayload.append(uint16: 0)                 // pre_defined

        var hdlrPayload = Data()
        hdlrPayload.append(uint32: 0)                 // version + flags
        hdlrPayload.append(uint32: 0)                 // pre_defined
        hdlrPayload.append(contentsOf: Array("vide".utf8))
        hdlrPayload.append(Data(repeating: 0, count: 12))
        hdlrPayload.append(contentsOf: Array("Handler\0".utf8))

        let mdia = box("mdia", box("mdhd", mdhdPayload)
                       + box("hdlr", hdlrPayload) + box("minf", stbl))

        var ftypPayload = Data("mp42".utf8)
        ftypPayload.append(uint32: 512)
        for brand in ["isom", "mp41", "mp42"] {
            ftypPayload.append(contentsOf: Array(brand.utf8))
        }

        return box("ftyp", ftypPayload)
            + box("moov", box("trak", mdia))
            + box("mdat", Data(repeating: 0xAB, count: 64))
    }

    private func transportStream(packets: Int = 8) -> Data {
        var ts = Data()
        for index in 0..<packets {
            ts.append(0x47)
            ts.append(Data(repeating: UInt8(index & 0xFF), count: 187))
        }
        return ts
    }

    // MARK: - Elementary stream probing

    func test_probe_h264ElementaryStream() throws {
        let result = try VideoProbe.probe(h264ElementaryStream(frames: 10))

        XCTAssertEqual(result.container, .elementaryStream)
        XCTAssertEqual(result.stream.codec, .h264)
        XCTAssertEqual(result.stream.width, 1920)
        XCTAssertEqual(result.stream.height, 1080)
        XCTAssertEqual(result.stream.profileIDC, 100)
        XCTAssertEqual(result.stream.levelTimesTen, 41)
        XCTAssertEqual(result.frameCount, 10)
        XCTAssertEqual(result.frameCountSource, .accessUnitScan,
                       "a raw stream has no sample table to consult")
    }

    /// An iPhone's `.MOV` is ISO-BMFF with an `mp42` brand and an `avcC` box whose
    /// SPS keeps its 0x67 NAL header. Feeding that byte to the SPS parser as if it
    /// were `profile_idc` yields 39, and High Profile input is rejected as
    /// non-conformant — so probing an MP4 has to strip the header first.
    func test_probe_mp4_readsProfileThroughAVCCNALHeader() throws {
        let result = try VideoProbe.probe(h264MP4(sps: Self.spsH264NAL, frames: 12))

        XCTAssertEqual(result.container, .mp4)
        XCTAssertEqual(result.stream.codec, .h264)
        XCTAssertEqual(result.stream.profileIDC, 100,
                       "0x67 is the NAL header, not profile_idc 39")
        XCTAssertEqual(result.stream.levelTimesTen, 41)
        XCTAssertEqual(result.stream.width, 1920)
        XCTAssertEqual(result.stream.height, 1080)
    }

    func test_probe_hevcElementaryStream() throws {
        let result = try VideoProbe.probe(hevcElementaryStream(frames: 5))
        XCTAssertEqual(result.stream.codec, .h265)
        XCTAssertEqual(result.stream.width, 1920)
        XCTAssertEqual(result.frameCount, 5)
    }

    func test_probe_mpeg2ElementaryStream() throws {
        let result = try VideoProbe.probe(mpeg2ElementaryStream(frames: 7))
        XCTAssertEqual(result.stream.codec, .mpeg2)
        XCTAssertEqual(result.stream.width, 720)
        XCTAssertEqual(result.stream.height, 576)
        XCTAssertEqual(result.frameCount, 7)
        XCTAssertEqual(try XCTUnwrap(result.frameRate), 25.0, accuracy: 0.001)
    }

    /// D179: a raw MPEG-2 stream whose slice start code 0x07 also reads as an H.264
    /// SPS NAL unit (type 7) is still MPEG-2: the sequence header (00 00 01 B3) is
    /// checked first, and the stream is offered to MPEG2 MP@ML (PS3.5 2026a 8.2.5).
    func test_probe_mpeg2ElementaryStreamIsNotTakenForH264() throws {
        var stream = mpeg2ElementaryStream(frames: 1)
        for slice in UInt8(1)...7 {
            stream.append(contentsOf: [0x00, 0x00, 0x01, slice, 0x33, 0x00, 0x7D])
            stream.append(contentsOf: [UInt8](repeating: 0xFF, count: 8))
        }
        XCTAssertNotNil(H264Parser.parseFirstSPS(annexB: stream),
                        "fixture: slice 0x07 parses as an H.264 SPS, the case that was misreported")
        let result = try VideoProbe.probe(stream)
        XCTAssertEqual(result.container, .elementaryStream)
        XCTAssertEqual(result.stream.codec, .mpeg2)
        XCTAssertEqual(result.stream.width, 720)
        XCTAssertEqual(result.stream.levelDescription, "Main")
        XCTAssertEqual(result.suggestedTransferSyntax, .mpeg2MainProfile)

        // D177: the MPEG-2 container is not constrained (8.2.5), so the raw stream is
        // planned for encapsulation; an H.264 elementary stream is still refused (8.2.7).
        let plan = try VideoWorkflow.planConversion(bitstream: stream)
        XCTAssertEqual(plan.transferSyntax, .mpeg2MainProfile)
        XCTAssertThrowsError(try VideoWorkflow.planConversion(bitstream: h264ElementaryStream(frames: 2)))
    }

    func test_probe_detectsCodecByContentNotExtension() throws {
        // The same bytes are identified regardless of what a filename claims.
        let h264 = try VideoProbe.probe(h264ElementaryStream(frames: 3))
        let hevc = try VideoProbe.probe(hevcElementaryStream(frames: 3))
        let mpeg2 = try VideoProbe.probe(mpeg2ElementaryStream(frames: 3))

        XCTAssertEqual(h264.stream.codec, .h264)
        XCTAssertEqual(hevc.stream.codec, .h265)
        XCTAssertEqual(mpeg2.stream.codec, .mpeg2)
    }

    // MARK: - Transfer syntax suggestion

    func test_probe_suggestsTransferSyntaxForConformantStream() throws {
        let result = try VideoProbe.probe(h264ElementaryStream(frames: 10))
        XCTAssertEqual(result.suggestedTransferSyntax?.uid, TransferSyntax.mpeg4AVCHP41.uid)
    }

    func test_probe_suggestsNothingForBaselineProfile() throws {
        // Baseline has no DICOM transfer syntax, so no suggestion is possible.
        let result = try VideoProbe.probe(
            h264ElementaryStream(frames: 3, sps: Self.spsBaselineNAL))
        XCTAssertEqual(result.stream.profileIDC, 66)
        XCTAssertNil(result.suggestedTransferSyntax)
    }

    func test_probedStream_validatesAgainstItsSuggestedSyntax() throws {
        // Probing and validation must agree, or the pipeline contradicts itself.
        let result = try VideoProbe.probe(h264ElementaryStream(frames: 10))
        let syntax = try XCTUnwrap(result.suggestedTransferSyntax)
        let conformance = VideoConformanceValidator.validate(
            stream: result.stream,
            transferSyntax: syntax,
            numberOfFrames: result.frameCount
        )
        XCTAssertTrue(conformance.isConformant, conformance.report)
    }

    // MARK: - Non-video guards (decision Q5)

    func test_probe_rejectsPNGWithPointerToDicomImage() {
        let png = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
        XCTAssertThrowsError(try VideoProbe.probe(png)) { error in
            guard let probeError = error as? VideoProbeError else {
                return XCTFail("expected a VideoProbeError, got \(error)")
            }
            XCTAssertEqual(probeError, .notVideo(detected: "a PNG image"))
            XCTAssertTrue(probeError.message.contains("dicom-image"),
                          "the rejection must redirect to the right tool")
        }
    }

    func test_probe_rejectsAnimatedGIF() {
        let gif = Data([0x47, 0x49, 0x46, 0x38, 0x39, 0x61, 0x00, 0x00])
        XCTAssertThrowsError(try VideoProbe.probe(gif)) { error in
            XCTAssertEqual(error as? VideoProbeError, .notVideo(detected: "an animated GIF"))
        }
    }

    func test_probe_rejectsTIFF() {
        for magic in [[0x49, 0x49, 0x2A, 0x00], [0x4D, 0x4D, 0x00, 0x2A]] {
            let tiff = Data(magic.map { UInt8($0) } + [0x08, 0x00, 0x00, 0x00])
            XCTAssertThrowsError(try VideoProbe.probe(tiff)) { error in
                XCTAssertEqual(error as? VideoProbeError, .notVideo(detected: "a TIFF image"))
            }
        }
    }

    func test_probe_rejectsJPEGAndBMPAndMatroska() {
        let cases: [([UInt8], String)] = [
            ([0xFF, 0xD8, 0xFF, 0xE0], "a JPEG image"),
            ([0x42, 0x4D, 0x00, 0x00], "a BMP image"),
            ([0x1A, 0x45, 0xDF, 0xA3], "a Matroska/WebM file"),
            ([0x52, 0x49, 0x46, 0x46], "a RIFF/AVI file"),
        ]
        for (magic, expected) in cases {
            XCTAssertThrowsError(try VideoProbe.probe(Data(magic + [0, 0, 0, 0]))) { error in
                XCTAssertEqual(error as? VideoProbeError, .notVideo(detected: expected))
            }
        }
    }

    func test_probe_rejectsDICOMInputByPreambleMagic() {
        // A DICOM file's "DICM" magic sits at offset 128, after the preamble.
        var dicom = Data(repeating: 0x00, count: 128)
        dicom.append(contentsOf: Array("DICM".utf8))
        dicom.append(Data(repeating: 0x00, count: 16))

        XCTAssertThrowsError(try VideoProbe.probe(dicom)) { error in
            XCTAssertEqual(error as? VideoProbeError, .notVideo(detected: "a DICOM file"))
        }
    }

    func test_detectNonVideo_passesRealVideoThrough() {
        XCTAssertNil(VideoProbe.detectNonVideo(h264ElementaryStream(frames: 2)))
        XCTAssertNil(VideoProbe.detectNonVideo(mpeg2ElementaryStream(frames: 2)))
    }

    // MARK: - MPEG-2 in MP4

    /// A minimal MP4 carrying one MPEG-2 track.
    ///
    /// - Parameters:
    ///   - inESDS: Whether to store the sequence header as an `esds`
    ///     DecoderSpecificInfo. When false the `esds` stops after the decoder
    ///     config, exactly as ffmpeg writes it, leaving the header only in `mdat`.
    private func mpeg2MP4(inESDS: Bool, frames: UInt32 = 50) -> Data {
        func box(_ type: String, _ payload: Data) -> Data {
            var data = Data()
            data.append(uint32: UInt32(payload.count + 8))
            data.append(contentsOf: Array(type.utf8))
            data.append(payload)
            return data
        }

        /// One MPEG-4 descriptor, with the base-128 size encoding `esds` uses.
        func descriptor(_ tag: UInt8, _ payload: Data) -> Data {
            var data = Data([tag])
            data.append(UInt8(payload.count))
            data.append(payload)
            return data
        }

        // DecoderConfigDescriptor: objectTypeIndication 0x61 is MPEG-2 Main.
        var decoderConfig = Data([0x61, 0x11])
        decoderConfig.append(Data(repeating: 0, count: 3))   // bufferSizeDB
        decoderConfig.append(uint32: 0x0007_BA3C)            // maxBitrate
        decoderConfig.append(uint32: 0x0007_BA3C)            // avgBitrate
        if inESDS {
            decoderConfig.append(descriptor(0x05, Data(Self.mpeg2SequenceHeader)))
        }

        var esPayload = Data()
        esPayload.append(uint16: 1)                          // ES_ID
        esPayload.append(0x00)                               // flags: no options
        esPayload.append(descriptor(0x04, decoderConfig))
        esPayload.append(descriptor(0x06, Data([0x02])))     // SLConfigDescriptor

        var esdsPayload = Data()
        esdsPayload.append(uint32: 0)                        // version + flags
        esdsPayload.append(descriptor(0x03, esPayload))
        let esds = box("esds", esdsPayload)

        var entry = Data(repeating: 0, count: 6)             // reserved
        entry.append(uint16: 1)                              // data_reference_index
        entry.append(uint16: 0)                              // pre_defined
        entry.append(uint16: 0)                              // reserved
        entry.append(Data(repeating: 0, count: 12))          // pre_defined
        entry.append(uint16: 720)
        entry.append(uint16: 576)
        entry.append(uint32: 0x0048_0000)                    // horizresolution
        entry.append(uint32: 0x0048_0000)                    // vertresolution
        entry.append(uint32: 0)                              // reserved
        entry.append(uint16: 1)                              // frame_count
        entry.append(Data(repeating: 0, count: 32))          // compressorname
        entry.append(uint16: 24)                             // depth
        entry.append(uint16: 0xFFFF)                         // pre_defined -1
        entry.append(esds)
        let mp4v = box("mp4v", entry)

        var stsdPayload = Data()
        stsdPayload.append(uint32: 0)                        // version + flags
        stsdPayload.append(uint32: 1)                        // entry_count
        stsdPayload.append(mp4v)

        var stszPayload = Data()
        stszPayload.append(uint32: 0)                        // version + flags
        stszPayload.append(uint32: 1000)                     // uniform sample_size
        stszPayload.append(uint32: frames)

        // The chunk offset is patched below, once the header sizes are known.
        var stcoPayload = Data()
        stcoPayload.append(uint32: 0)                        // version + flags
        stcoPayload.append(uint32: 1)                        // entry_count
        stcoPayload.append(uint32: 0)                        // placeholder offset

        let stbl = box("stbl", box("stsd", stsdPayload)
                      + box("stsz", stszPayload) + box("stco", stcoPayload))

        var mdhdPayload = Data()
        mdhdPayload.append(uint32: 0)                        // version + flags
        mdhdPayload.append(uint32: 0)                        // creation_time
        mdhdPayload.append(uint32: 0)                        // modification_time
        mdhdPayload.append(uint32: 25)                       // timescale
        mdhdPayload.append(uint32: frames)                   // duration
        mdhdPayload.append(uint16: 0x55C4)                   // language
        mdhdPayload.append(uint16: 0)                        // pre_defined

        var hdlrPayload = Data()
        hdlrPayload.append(uint32: 0)                        // version + flags
        hdlrPayload.append(uint32: 0)                        // pre_defined
        hdlrPayload.append(contentsOf: Array("vide".utf8))
        hdlrPayload.append(Data(repeating: 0, count: 12))
        hdlrPayload.append(contentsOf: Array("Handler\0".utf8))

        let mdia = box("mdia", box("mdhd", mdhdPayload)
                       + box("hdlr", hdlrPayload) + box("minf", stbl))

        var ftypPayload = Data("mp42".utf8)
        ftypPayload.append(uint32: 512)
        for brand in ["isom", "mp41", "mp42"] {
            ftypPayload.append(contentsOf: Array(brand.utf8))
        }

        // Samples open with the sequence header, the way MPEG-2 carries it in
        // band; the header sits 8 bytes into `mdat`, past that box's own header.
        var samples = Data(Self.mpeg2SequenceHeader)
        samples.append(contentsOf: [0x00, 0x00, 0x01, 0x00, 0x00, 0x0F, 0xFF, 0xF8])

        let header = box("ftyp", ftypPayload) + box("moov", box("trak", mdia))
        var file = header + box("mdat", samples)

        // Point stco at the first sample, which follows the `mdat` box header.
        let sampleStart = UInt32(header.count + 8)
        guard let stcoRange = file.range(of: Data("stco".utf8)) else { return file }
        let offsetStart = stcoRange.upperBound + 8
        file.replaceSubrange(
            offsetStart..<(offsetStart + 4),
            with: withUnsafeBytes(of: sampleStart.bigEndian) { Data($0) })
        return file
    }

    /// An `esds` is the documented home for a sequence header, so it is preferred
    /// when a muxer writes one.
    func test_probe_mpeg2MP4ReadsSequenceHeaderFromESDS() throws {
        let result = try VideoProbe.probe(mpeg2MP4(inESDS: true))

        XCTAssertEqual(result.container, .mp4)
        XCTAssertEqual(result.stream.codec, .mpeg2)
        XCTAssertEqual(result.stream.width, 720)
        XCTAssertEqual(result.stream.height, 576)
        XCTAssertEqual(result.frameCount, 50)
        XCTAssertEqual(result.suggestedTransferSyntax, .mpeg2MainProfile)
    }

    /// ffmpeg writes an `esds` with no DecoderSpecificInfo at all, because MPEG-2
    /// repeats its sequence header in band. Such a file must still convert.
    func test_probe_mpeg2MP4FallsBackToFirstSample() throws {
        let result = try VideoProbe.probe(mpeg2MP4(inESDS: false))

        XCTAssertEqual(result.container, .mp4)
        XCTAssertEqual(result.stream.codec, .mpeg2)
        XCTAssertEqual(result.stream.width, 720)
        XCTAssertEqual(result.stream.height, 576)
        XCTAssertEqual(result.suggestedTransferSyntax, .mpeg2MainProfile)
    }

    // MARK: - Transport stream (decision Q2)

    func test_probe_transportStreamRejectedWithoutTrustInput() {
        XCTAssertThrowsError(try VideoProbe.probe(transportStream())) { error in
            guard let probeError = error as? VideoProbeError else {
                return XCTFail("expected a VideoProbeError")
            }
            XCTAssertEqual(probeError, .transportStreamNotValidatable)
            XCTAssertTrue(probeError.message.contains("--trust-input"))
            XCTAssertTrue(probeError.message.contains("ffmpeg"))
        }
    }

    func test_probe_transportStreamAcceptedWithTrustInput() throws {
        // MPEG-TS is one of the two containers PS3.5 blesses, so passing a
        // conformant one through is legal even without demuxing it.
        let result = try VideoProbe.probe(transportStream(), trustInput: true)
        XCTAssertEqual(result.container, .mpegTS)
        XCTAssertEqual(result.frameCountSource, .unavailable,
                       "nothing was read, so nothing is claimed")
        XCTAssertNil(result.suggestedTransferSyntax,
                     "an unvalidated stream gets no automatic transfer syntax")
    }

    /// Builds a transport stream carrying a PAT, a PMT and one video PID.
    ///
    /// - Parameters:
    ///   - streamType: The PMT stream type, which names the codec.
    ///   - elementaryStream: The bytes to carry on the video PID.
    private func transportStream(streamType: UInt8, elementaryStream: Data) -> Data {
        let videoPID = 0x0100
        let pmtPID = 0x1000

        /// Wraps a payload in a 188-byte packet, padding with the 0xFF stuffing a
        /// real muxer uses.
        func packet(pid: Int, payloadStart: Bool, payload: Data) -> Data {
            var data = Data([0x47])
            data.append(UInt8((payloadStart ? 0x40 : 0x00) | (pid >> 8) & 0x1F))
            data.append(UInt8(pid & 0xFF))
            data.append(0x10)  // payload only, continuity counter 0
            let body = payload.prefix(184)
            data.append(body)
            data.append(Data(repeating: 0xFF, count: 184 - body.count))
            return data
        }

        /// A PSI section, led by its pointer_field and trailed by a stub CRC.
        func section(tableID: UInt8, body: Data) -> Data {
            // section_length covers everything after it, the 4-byte CRC included.
            let length = body.count + 4
            var data = Data([0x00, tableID])
            data.append(UInt8(0xB0 | ((length >> 8) & 0x0F)))
            data.append(UInt8(length & 0xFF))
            data.append(body)
            data.append(Data(repeating: 0x00, count: 4))  // CRC_32, unchecked here
            return data
        }

        // PAT: one program pointing at the PMT.
        var patBody = Data([0x00, 0x01, 0xC1, 0x00, 0x00])  // ids, version, numbers
        patBody.append(contentsOf: [0x00, 0x01])            // program_number 1
        patBody.append(UInt8(0xE0 | ((pmtPID >> 8) & 0x1F)))
        patBody.append(UInt8(pmtPID & 0xFF))

        // PMT: one elementary stream of the given type.
        var pmtBody = Data([0x00, 0x01, 0xC1, 0x00, 0x00])  // ids, version, numbers
        pmtBody.append(UInt8(0xE0 | ((videoPID >> 8) & 0x1F)))
        pmtBody.append(UInt8(videoPID & 0xFF))              // PCR_PID
        pmtBody.append(contentsOf: [0xF0, 0x00])            // program_info_length 0
        pmtBody.append(streamType)
        pmtBody.append(UInt8(0xE0 | ((videoPID >> 8) & 0x1F)))
        pmtBody.append(UInt8(videoPID & 0xFF))
        pmtBody.append(contentsOf: [0xF0, 0x00])            // ES_info_length 0

        // A PES header, whose payload is the elementary stream itself.
        var pes = Data([0x00, 0x00, 0x01, 0xE0])
        pes.append(uint16: 0)                               // PES_packet_length 0
        pes.append(contentsOf: [0x80, 0x00, 0x00])          // flags, no optional fields
        pes.append(elementaryStream)

        var ts = Data()
        ts.append(packet(pid: 0x0000, payloadStart: true,
                         payload: section(tableID: 0x00, body: patBody)))
        ts.append(packet(pid: pmtPID, payloadStart: true,
                         payload: section(tableID: 0x02, body: pmtBody)))
        ts.append(packet(pid: videoPID, payloadStart: true, payload: pes))
        // Trailing packets give the sync detector the run of packets it wants.
        for _ in 0..<4 {
            ts.append(packet(pid: videoPID, payloadStart: false, payload: Data()))
        }
        return ts
    }

    /// Rows and Columns are required attributes, so a trusted stream still has to
    /// yield real geometry: an object carrying zeroes is one no reader can show.
    func test_probe_trustedTransportStreamReadsMPEG2Geometry() throws {
        let ts = transportStream(streamType: 0x02,
                                 elementaryStream: mpeg2ElementaryStream(frames: 4))
        let result = try VideoProbe.probe(ts, trustInput: true)

        XCTAssertEqual(result.container, .mpegTS)
        XCTAssertEqual(result.stream.codec, .mpeg2)
        XCTAssertEqual(result.stream.width, 720)
        XCTAssertEqual(result.stream.height, 576)
    }

    /// The PMT names the codec, and it is believed over the payload's own shape.
    /// MPEG-2 start codes share the Annex B prefix, so sniffing would read an
    /// MPEG-2 sequence header as a plausible — and wrong — H.264 SPS.
    func test_probe_trustedTransportStreamTrustsPMTCodecOverSniffing() throws {
        let ts = transportStream(streamType: 0x1B,
                                 elementaryStream: h264ElementaryStream(frames: 4))
        let result = try VideoProbe.probe(ts, trustInput: true)

        XCTAssertEqual(result.stream.codec, .h264)
        XCTAssertEqual(result.stream.width, 1920)
        XCTAssertEqual(result.stream.height, 1080)
    }

    /// A PID carrying something unreadable still encapsulates, since the caller
    /// asserted conformance — but nothing is claimed about it.
    func test_probe_trustedTransportStreamWithoutReadableVideoClaimsNothing() throws {
        let result = try VideoProbe.probe(transportStream(), trustInput: true)

        XCTAssertEqual(result.stream.codec, .unknown)
        XCTAssertEqual(result.stream.width, 0)
        XCTAssertNil(result.suggestedTransferSyntax)
    }

    // MARK: - Unrecognized input

    func test_probe_rejectsUnrecognizedBytes() {
        XCTAssertThrowsError(try VideoProbe.probe(Data([0x12, 0x34, 0x56, 0x78]))) { error in
            XCTAssertEqual(error as? VideoProbeError, .unrecognizedFormat)
        }
    }

    func test_probe_rejectsEmptyInput() {
        XCTAssertThrowsError(try VideoProbe.probe(Data())) { error in
            XCTAssertEqual(error as? VideoProbeError, .unrecognizedFormat)
        }
    }

    func test_probe_rejectsAnnexBWithNoParameterSet() {
        // Start codes but no SPS: nothing can be validated.
        let stream = Data([0x00, 0x00, 0x00, 0x01, 0x68, 0xEE, 0x3C, 0x80])
        XCTAssertThrowsError(try VideoProbe.probe(stream)) { error in
            XCTAssertEqual(error as? VideoProbeError, .unrecognizedFormat)
        }
    }

    // MARK: - Error messages

    func test_everyProbeError_hasAnActionableMessage() {
        let errors: [VideoProbeError] = [
            .unrecognizedFormat,
            .noVideoTrack,
            .multipleVideoTracks(count: 2),
            .unsupportedCodec("VP9"),
            .parameterSetsUnreadable,
            .transportStreamNotValidatable,
            .notVideo(detected: "a PNG image"),
        ]
        for error in errors {
            XCTAssertFalse(error.message.isEmpty, "\(error) has no message")
            XCTAssertTrue(error.message.hasPrefix("error:"), "\(error) should read as an error")
        }
    }

    func test_multipleVideoTracks_messageNamesTheCount() {
        let error = VideoProbeError.multipleVideoTracks(count: 3)
        XCTAssertTrue(error.message.contains("3 video tracks"), error.message)
        XCTAssertTrue(error.message.contains("ffmpeg"), "a remedy is given")
    }

    // MARK: - Robustness

    func test_probe_truncatedStreamsDoNotCrash() {
        let stream = h264ElementaryStream(frames: 5)
        for length in stride(from: 1, to: stream.count, by: 3) {
            _ = try? VideoProbe.probe(stream.prefix(length))
        }
    }

    func test_probe_randomBytesDoNotCrash() {
        var generator = SystemRandomNumberGenerator()
        for _ in 0..<100 {
            var bytes = Data()
            for _ in 0..<96 { bytes.append(UInt8.random(in: 0...255, using: &generator)) }
            _ = try? VideoProbe.probe(bytes)
        }
    }
}
