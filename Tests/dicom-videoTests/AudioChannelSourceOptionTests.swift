//
// AudioChannelSourceOptionTests.swift
// dicom-video
//
// D56: `dicom-video convert --audio-channel-source` names the PS3.16 2026a CID 3000
// Audio Channel Source (6 rows: DCM 109110–109115) the engine writes as the Channel
// Source Sequence (003A,0208) of each Multiplexed Audio Channels Description Code
// Sequence (003A,0300) Item (PS3.3 2026a Table C.7-13). Without it the sequence has
// no Items. The MP4 fixture is the one VideoAudioTests (DICOMKitTests) uses: an H.264
// High@4.1 track plus one AAC LC 48 kHz stereo track.
//

import XCTest
import ArgumentParser
import DICOMKit
import DICOMCore
@testable import dicom_video

final class AudioChannelSourceOptionTests: XCTestCase {

    // MARK: - CID 3000 table

    /// PS3.16 2026a CID 3000 Audio Channel Source, as dumped from the DocBook.
    private static let cid3000: [(keyword: String, value: String, meaning: String)] = [
        ("voice", "109110", "Voice"),
        ("operators-narrative", "109111", "Operator's narrative"),
        ("ambient-room-environment", "109112", "Ambient room environment"),
        ("doppler-audio", "109113", "Doppler audio"),
        ("phonocardiogram", "109114", "Phonocardiogram"),
        ("physiological-audio-signal", "109115", "Physiological audio signal"),
    ]

    func test_keywords_areTheSixRowsOfCID3000() {
        XCTAssertEqual(AudioChannelSourceOption.keywords.count, 6)
        for (row, entry) in zip(Self.cid3000, AudioChannelSourceOption.keywords) {
            XCTAssertEqual(entry.keyword, row.keyword)
            XCTAssertEqual(entry.source.codingSchemeDesignator, "DCM")
            XCTAssertEqual(entry.source.codeValue, row.value)
            XCTAssertEqual(entry.source.codeMeaning, row.meaning)
            XCTAssertTrue(entry.source.isCID3000Member)
        }
        XCTAssertEqual(AudioChannelSourceOption.keywords.map(\.source), VideoAudioChannel.Source.cid3000)
    }

    func test_help_namesCID3000TheSequenceAndEveryKeyword() {
        let help = AudioChannelSourceOption.help
        XCTAssertTrue(help.contains("CID 3000"))
        XCTAssertTrue(help.contains("(003A,0300)"))
        XCTAssertTrue(help.contains("(003A,0208)"))
        for row in Self.cid3000 { XCTAssertTrue(help.contains(row.keyword), row.keyword) }
    }

    // MARK: - Parsing

    func test_parse_keyword_isCaseInsensitive() throws {
        XCTAssertEqual(try AudioChannelSourceOption.parse("voice"), .voice)
        XCTAssertEqual(try AudioChannelSourceOption.parse("Doppler-Audio"), .dopplerAudio)
        XCTAssertEqual(try AudioChannelSourceOption.parse(" phonocardiogram "), .phonocardiogram)
    }

    func test_parse_schemeValue_forAListedCode_takesTheCIDMeaning() throws {
        let source = try AudioChannelSourceOption.parse("DCM:109111")
        XCTAssertEqual(source, .operatorsNarrative)
        XCTAssertEqual(source.codeMeaning, "Operator's narrative")
    }

    func test_parse_schemeValueMeaning_acceptsAnUnlistedCode() throws {
        // CID 3000 is "Type: Extensible".
        let source = try AudioChannelSourceOption.parse("99LOCAL:AUD1:Ultrasound microphone")
        XCTAssertEqual(source.codingSchemeDesignator, "99LOCAL")
        XCTAssertEqual(source.codeValue, "AUD1")
        XCTAssertEqual(source.codeMeaning, "Ultrasound microphone")
        XCTAssertFalse(source.isCID3000Member)
    }

    func test_parse_rejectsUnknownKeywordAndMissingMeaning() {
        XCTAssertThrowsError(try AudioChannelSourceOption.parse("narration")) { error in
            XCTAssertEqual(error as? AudioChannelSourceOption.ParseError, .unknown("narration"))
            XCTAssertTrue("\(error)".contains("--audio-channel-source"))
        }
        XCTAssertThrowsError(try AudioChannelSourceOption.parse("99LOCAL:AUD1")) { error in
            XCTAssertEqual(error as? AudioChannelSourceOption.ParseError, .missingMeaning("99LOCAL:AUD1"))
        }
        XCTAssertThrowsError(try AudioChannelSourceOption.parse("DCM:")) { error in
            XCTAssertEqual(error as? AudioChannelSourceOption.ParseError, .unknown("DCM:"))
        }
    }

    // MARK: - Option → Metadata

    func test_option_reachesMetadataAudioChannelSource() throws {
        let with = try MetadataOptions.parse(["--audio-channel-source", "voice"])
        XCTAssertEqual(try with.validatedShared().audioChannelSource, .voice)
        XCTAssertNil(with.shared.audioChannelSource, "the unvalidated value never carries it")

        let without = try MetadataOptions.parse([])
        XCTAssertNil(try without.validatedShared().audioChannelSource)

        let bad = try MetadataOptions.parse(["--audio-channel-source", "narration"])
        XCTAssertThrowsError(try bad.validatedShared())
    }

    /// P-AUDIO-SOURCE-PER-TRACK: repeated values are one source per audio track.
    func test_repeatedOption_reachesMetadataAudioChannelSources() throws {
        let once = try MetadataOptions.parse(["--audio-channel-source", "voice"])
        XCTAssertNil(try once.validatedShared().audioChannelSources, "one value: the default for every track")
        let twice = try MetadataOptions.parse(["--audio-channel-source", "voice", "--audio-channel-source", "DCM:109113"])
        let metadata = try twice.validatedShared()
        XCTAssertNil(metadata.audioChannelSource)
        XCTAssertEqual(metadata.audioChannelSources, [.voice, .dopplerAudio])
        let bad = try MetadataOptions.parse(["--audio-channel-source", "voice", "--audio-channel-source", "narration"])
        XCTAssertThrowsError(try bad.validatedShared())
    }

    func test_batchOptions_acceptTheOption() throws {
        let batch = try DICOMVideo.Batch.parse(["clips", "--output-dir", "out", "--audio-channel-source", "DCM:109113"])
        XCTAssertEqual(try batch.metadata.validatedShared().audioChannelSource, .dopplerAudio)
    }

    // MARK: - convert end to end

    func test_convert_withOption_writesOneItemPerTrackWithTheCode() throws {
        let (input, output) = try temporaryPaths()
        try mp4(audioEntry: aacEntry(rate: 48000, dsi: Self.ascLC48Stereo)).write(to: input)

        var convert = try DICOMVideo.Convert.parse([
            input.path, "--output", output.path, "--type", "endoscopic",
            "--audio-channel-source", "operators-narrative",
        ])
        try convert.run()

        let file = try DICOMFile.read(from: try Data(contentsOf: output))
        let items = try XCTUnwrap(file.dataSet[Tag(group: 0x003A, element: 0x0300)]?.sequenceItems)
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items[0].string(for: Tag(group: 0x003A, element: 0x0301)), "1")
        XCTAssertEqual(items[0].string(for: Tag(group: 0x003A, element: 0x0302)), "STEREO")
        let codes = try XCTUnwrap(items[0][Tag(group: 0x003A, element: 0x0208)]?.sequenceItems)
        XCTAssertEqual(codes.count, 1, "Channel Source Sequence: only a single Item")
        XCTAssertEqual(codes[0].string(for: Tag(group: 0x0008, element: 0x0100)), "109111")
        XCTAssertEqual(codes[0].string(for: Tag(group: 0x0008, element: 0x0102)), "DCM")
        XCTAssertEqual(codes[0].string(for: Tag(group: 0x0008, element: 0x0104)), "Operator's narrative")

        let parsed = try VideoParser.parse(from: file.dataSet)
        XCTAssertEqual(parsed.multiplexedAudioChannels, [
            VideoAudioChannel(channelIdentificationCode: 1, mode: .stereo, source: .operatorsNarrative),
        ])
    }

    /// More values than audio tracks: exit 1 and nothing written.
    func test_convert_moreValuesThanTracks_exitsOne() throws {
        let (input, output) = try temporaryPaths()
        try mp4(audioEntry: aacEntry(rate: 48000, dsi: Self.ascLC48Stereo)).write(to: input)
        var convert = try DICOMVideo.Convert.parse([
            input.path, "--output", output.path, "--type", "endoscopic",
            "--audio-channel-source", "voice", "--audio-channel-source", "doppler-audio",
        ])
        XCTAssertThrowsError(try convert.run()) {
            XCTAssertEqual(($0 as? ExitCode)?.rawValue, 1, "\($0)")
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: output.path))
    }

    func test_convert_withoutOption_leavesTheSequenceEmpty() throws {
        let (input, output) = try temporaryPaths()
        try mp4(audioEntry: aacEntry(rate: 48000, dsi: Self.ascLC48Stereo)).write(to: input)

        var convert = try DICOMVideo.Convert.parse([input.path, "--output", output.path, "--type", "endoscopic"])
        try convert.run()

        let file = try DICOMFile.read(from: try Data(contentsOf: output))
        let sequence = try XCTUnwrap(file.dataSet[Tag(group: 0x003A, element: 0x0300)],
                                     "(003A,0300) is Type 2C: present, with no Items")
        XCTAssertEqual(sequence.sequenceItems?.count ?? 0, 0)
    }

    // MARK: - Fixtures (as VideoAudioTests)

    private func temporaryPaths() throws -> (input: URL, output: URL) {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("dicom-videoTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }
        return (dir.appendingPathComponent("clip.mp4"), dir.appendingPathComponent("clip.dcm"))
    }

    private func box(_ type: String, _ payload: Data) -> Data {
        var data = Data()
        data.append(uint32: UInt32(payload.count + 8))
        data.append(contentsOf: Array(type.utf8))
        data.append(payload)
        return data
    }

    private func fullBox(_ type: String, _ payload: Data) -> Data {
        box(type, Data([0, 0, 0, 0]) + payload)
    }

    private func ftyp() -> Data {
        var payload = Data("isom".utf8)
        payload.append(uint32: 512)
        for brand in ["isom", "mp41", "avc1"] { payload.append(contentsOf: Array(brand.utf8)) }
        return box("ftyp", payload)
    }

    private func mdhd(timescale: UInt32, duration: UInt32) -> Data {
        var payload = Data()
        payload.append(uint32: 0)
        payload.append(uint32: 0)
        payload.append(uint32: 0)
        payload.append(uint32: timescale)
        payload.append(uint32: duration)
        payload.append(uint16: 0x55C4)
        payload.append(uint16: 0)
        return box("mdhd", payload)
    }

    private func hdlr(_ handler: String) -> Data {
        var payload = Data()
        payload.append(uint32: 0)
        payload.append(uint32: 0)
        payload.append(contentsOf: Array(handler.utf8))
        payload.append(Data(repeating: 0, count: 12))
        payload.append(contentsOf: Array("Handler\0".utf8))
        return box("hdlr", payload)
    }

    private static let spsH264Unit = Data([
        0x67,
        0x64, 0x00, 0x29, 0xAC, 0xB4, 0x03, 0xC0, 0x11, 0x3F, 0x2C, 0x20,
        0x00, 0x00, 0x03, 0x00, 0x20, 0x00, 0x00, 0x07, 0x98,
    ])

    private func avc1Entry() -> Data {
        var avcC = Data([0x01, 0x64, 0x00, 0x29, 0xFF, 0xE1])
        avcC.append(uint16: UInt16(Self.spsH264Unit.count))
        avcC.append(Self.spsH264Unit)
        avcC.append(0x01)
        avcC.append(uint16: 3)
        avcC.append(contentsOf: [0xEE, 0x3C, 0xB0])

        var payload = Data(repeating: 0, count: 6)
        payload.append(uint16: 1)
        payload.append(Data(repeating: 0, count: 16))
        payload.append(uint16: 1920)
        payload.append(uint16: 1080)
        payload.append(uint32: 0x0048_0000)
        payload.append(uint32: 0x0048_0000)
        payload.append(uint32: 0)
        payload.append(uint16: 1)
        payload.append(Data(repeating: 0, count: 32))
        payload.append(uint16: 24)
        payload.append(uint16: 0xFFFF)
        payload.append(box("avcC", avcC))
        return box("avc1", payload)
    }

    private func audioEntry(
        _ format: String, channels: UInt16, sampleSize: UInt16, rate: UInt32, children: Data = Data()
    ) -> Data {
        var payload = Data(repeating: 0, count: 6)
        payload.append(uint16: 1)
        payload.append(Data(repeating: 0, count: 8))
        payload.append(uint16: channels)
        payload.append(uint16: sampleSize)
        payload.append(uint16: 0)
        payload.append(uint16: 0)
        payload.append(uint32: rate << 16)
        payload.append(children)
        return box(format, payload)
    }

    private func esds(objectType: UInt8, maxBitrate: UInt32, avgBitrate: UInt32, dsi: [UInt8]) -> Data {
        func descriptor(_ tag: UInt8, _ body: Data) -> Data {
            Data([tag, UInt8(body.count)]) + body
        }
        var config = Data([objectType, 0x15, 0x00, 0x00, 0x00])
        config.append(uint32: maxBitrate)
        config.append(uint32: avgBitrate)
        config.append(descriptor(0x05, Data(dsi)))
        let es = Data([0x00, 0x01, 0x00]) + descriptor(0x04, config) + descriptor(0x06, Data([0x02]))
        return fullBox("esds", descriptor(0x03, es))
    }

    private func track(handler: String, entry: Data, samples: UInt32, chunkOffset: UInt32? = nil) -> Data {
        var stsd = Data()
        stsd.append(uint32: 0)
        stsd.append(uint32: 1)
        stsd.append(entry)
        var stsz = Data()
        stsz.append(uint32: 0)
        stsz.append(uint32: 100)
        stsz.append(uint32: samples)
        var stbl = box("stsd", stsd) + box("stsz", stsz)
        if let chunkOffset {
            var stco = Data()
            stco.append(uint32: 0)
            stco.append(uint32: 1)
            stco.append(uint32: chunkOffset)
            stbl += box("stco", stco)
        }
        let mdia = box("mdia", mdhd(timescale: 30000, duration: 300_000) + hdlr(handler)
                       + box("minf", box("stbl", stbl)))
        return box("trak", mdia)
    }

    /// An H.264 High@4.1 clip with one audio track; `mdat` precedes `moov`.
    private func mp4(audioEntry entry: Data, mdat: Data = Data(repeating: 0, count: 16)) -> Data {
        let head = ftyp()
        let mdatBox = box("mdat", mdat)
        let video = track(handler: "vide", entry: avc1Entry(), samples: 300)
        let audio = track(handler: "soun", entry: entry, samples: 400,
                          chunkOffset: UInt32(head.count + 8))
        return head + mdatBox + box("moov", video + audio)
    }

    private func aacEntry(rate: UInt32, dsi: [UInt8]) -> Data {
        audioEntry("mp4a", channels: 2, sampleSize: 16, rate: rate,
                   children: esds(objectType: 0x40, maxBitrate: 192_000, avgBitrate: 128_000, dsi: dsi))
    }

    /// AudioSpecificConfig AAC LC (2), 48 kHz (index 3), channelConfiguration 2.
    private static let ascLC48Stereo: [UInt8] = [0x11, 0x90]
}

private extension Data {
    mutating func append(uint32 value: UInt32) {
        append(contentsOf: [UInt8(value >> 24), UInt8((value >> 16) & 0xFF), UInt8((value >> 8) & 0xFF), UInt8(value & 0xFF)])
    }

    mutating func append(uint16 value: UInt16) {
        append(contentsOf: [UInt8(value >> 8), UInt8(value & 0xFF)])
    }
}
