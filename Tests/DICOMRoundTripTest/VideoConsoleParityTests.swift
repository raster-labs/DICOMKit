// VideoConsoleParityTests.swift
// Locks the console text and workflow behaviour that `dicom-video` shares with
// DICOMStudio's CLI Workshop.
//
// `dicom-video` was brought into the Workshop by lifting the whole of its CLI
// body — planning, building, batch orchestration, every printed line — out of
// `Sources/dicom-video/main.swift` and into `VideoWorkflow` + `VideoConsole`.
// Both surfaces now call the same functions, so the drift these tests guard
// against would have to be introduced deliberately, by editing the shared text
// here rather than in one adapter.
//
// The fixtures are ISO-BMFF files assembled from the box layouts in the
// specifications, the same way `MP4ContainerParserTests` builds them, so the
// expected values follow from the standard rather than from an encoder.
//
// Verified against source:
//   Sources/DICOMKit/Video/VideoConsole.swift  + Sources/dicom-video/main.swift
//   Sources/DICOMKit/Video/VideoWorkflow.swift + Sources/DICOMStudio/ViewModels/
//                                                CLIWorkshopViewModel.swift

import XCTest
import Foundation
@testable import DICOMKit
import DICOMCore

/// Big-endian appends, since every ISO-BMFF field is network byte order.
private extension Data {
    mutating func appendBE32(_ value: UInt32) {
        Swift.withUnsafeBytes(of: value.bigEndian) { self.append(contentsOf: $0) }
    }
    mutating func appendBE16(_ value: UInt16) {
        Swift.withUnsafeBytes(of: value.bigEndian) { self.append(contentsOf: $0) }
    }
}

final class VideoConsoleParityTests: XCTestCase {

    // MARK: - Fixture Construction

    private func box(_ type: String, _ payload: Data) -> Data {
        var data = Data()
        data.appendBE32(UInt32(payload.count + 8))
        data.append(contentsOf: Array(type.utf8))
        data.append(payload)
        return data
    }

    private func ftyp(major: String = "isom",
                      compatible: [String] = ["isom", "mp41", "avc1"]) -> Data {
        var payload = Data(major.utf8)
        payload.appendBE32(512)
        for brand in compatible { payload.append(contentsOf: Array(brand.utf8)) }
        return box("ftyp", payload)
    }

    private func mdhd(timescale: UInt32, duration: UInt32) -> Data {
        var payload = Data()
        payload.appendBE32(0)
        payload.appendBE32(0)
        payload.appendBE32(0)
        payload.appendBE32(timescale)
        payload.appendBE32(duration)
        payload.appendBE16(0x55C4)
        payload.appendBE16(0)
        return box("mdhd", payload)
    }

    private func hdlr(handler: String) -> Data {
        var payload = Data()
        payload.appendBE32(0)
        payload.appendBE32(0)
        payload.append(contentsOf: Array(handler.utf8))
        payload.append(Data(repeating: 0, count: 12))
        payload.append(contentsOf: Array("Handler\0".utf8))
        return box("hdlr", payload)
    }

    /// An AVCDecoderConfigurationRecord: parameter sets stored without their NAL
    /// headers and length-prefixed (ISO/IEC 14496-15 5.3.3.1).
    private func avcC(sps: [Data], pps: [Data]) -> Data {
        var payload = Data([0x01, 0x64, 0x00, 0x29, 0xFF])
        payload.append(UInt8(0xE0 | sps.count))
        for set in sps {
            payload.appendBE16(UInt16(set.count))
            payload.append(set)
        }
        payload.append(UInt8(pps.count))
        for set in pps {
            payload.appendBE16(UInt16(set.count))
            payload.append(set)
        }
        return box("avcC", payload)
    }

    private func visualSampleEntry(
        format: String, width: UInt16, height: UInt16, extensions: Data
    ) -> Data {
        var payload = Data(repeating: 0, count: 6)
        payload.appendBE16(1)
        payload.appendBE16(0)
        payload.appendBE16(0)
        payload.append(Data(repeating: 0, count: 12))
        payload.appendBE16(width)
        payload.appendBE16(height)
        payload.appendBE32(0x0048_0000)
        payload.appendBE32(0x0048_0000)
        payload.appendBE32(0)
        payload.appendBE16(1)
        payload.append(Data(repeating: 0, count: 32))
        payload.appendBE16(24)
        payload.appendBE16(0xFFFF)
        XCTAssertEqual(payload.count, 78, "VisualSampleEntry payload is 78 bytes")
        payload.append(extensions)
        return box(format, payload)
    }

    private func stsz(sampleCount: UInt32) -> Data {
        var payload = Data()
        payload.appendBE32(0)
        payload.appendBE32(1000)
        payload.appendBE32(sampleCount)
        return box("stsz", payload)
    }

    private func stsd(_ entry: Data) -> Data {
        var payload = Data()
        payload.appendBE32(0)
        payload.appendBE32(1)
        payload.append(entry)
        return box("stsd", payload)
    }

    private func videoTrack(
        sampleEntry: Data, frameCount: UInt32, timescale: UInt32 = 30000,
        duration: UInt32, handler: String = "vide"
    ) -> Data {
        let stbl = box("stbl", stsd(sampleEntry) + stsz(sampleCount: frameCount))
        let minf = box("minf", stbl)
        let mdia = box("mdia", mdhd(timescale: timescale, duration: duration)
                       + hdlr(handler: handler) + minf)
        return box("trak", mdia)
    }

    private func mp4File(tracks: [Data], major: String = "isom",
                         compatible: [String] = ["isom", "mp41", "avc1"]) -> Data {
        var moovPayload = Data()
        for track in tracks { moovPayload.append(track) }
        return ftyp(major: major, compatible: compatible)
            + box("moov", moovPayload)
            + box("mdat", Data(repeating: 0xAB, count: 64))
    }

    /// The 1080p High@4.1 SPS with its 0x67 NAL header, as avcC stores it:
    /// ISO/IEC 14496-15 keeps whole NAL units in the configuration record.
    private static let spsH264Unit = Data([
        0x67,
        0x64, 0x00, 0x29, 0xAC, 0xB4, 0x03, 0xC0, 0x11, 0x3F, 0x2C, 0x20,
        0x00, 0x00, 0x03, 0x00, 0x20, 0x00, 0x00, 0x07, 0x98,
    ])

    /// A conformant 1080p30 High@4.1 clip in an MP4 container.
    private func h264MP4(frameCount: UInt32 = 300) -> Data {
        let entry = visualSampleEntry(
            format: "avc1", width: 1920, height: 1080,
            extensions: avcC(sps: [Self.spsH264Unit], pps: [Data([0xEE, 0x3C, 0xB0])])
        )
        return mp4File(tracks: [videoTrack(
            sampleEntry: entry, frameCount: frameCount, duration: 300_000)])
    }

    /// The same clip carrying an audio track. DICOM video may carry audio
    /// (PS3.5 8.2.7-8.2.12, Table 8.2.12-1 allows AAC, MP3 and MP2 in MP4).
    private func h264MP4WithAudio() -> Data {
        let entry = visualSampleEntry(
            format: "avc1", width: 1920, height: 1080,
            extensions: avcC(sps: [Self.spsH264Unit], pps: [Data([0xEE, 0x3C, 0xB0])])
        )
        let video = videoTrack(sampleEntry: entry, frameCount: 300, duration: 300_000)
        let audio = videoTrack(
            sampleEntry: box("mp4a", Data(repeating: 0, count: 28)),
            frameCount: 400, duration: 300_000, handler: "soun")
        return mp4File(tracks: [video, audio])
    }

    /// A QuickTime-brand file: ISO-BMFF, but not a container DICOM permits.
    private func quickTimeMOV() -> Data {
        let entry = visualSampleEntry(
            format: "avc1", width: 1920, height: 1080,
            extensions: avcC(sps: [Self.spsH264Unit], pps: []))
        return mp4File(
            tracks: [videoTrack(sampleEntry: entry, frameCount: 300, duration: 300_000)],
            major: "qt  ", compatible: ["qt  "])
    }

    // MARK: - Exit Codes

    /// 0 success, 1 I/O or usage error, 2 conformance rejection — the contract
    /// scripts rely on, and the app's status badge maps from.
    func testExitCodesMatchTheDocumentedContract() {
        XCTAssertEqual(VideoConsole.ExitCode.success.rawValue, 0)
        XCTAssertEqual(VideoConsole.ExitCode.inputError.rawValue, 1)
        XCTAssertEqual(VideoConsole.ExitCode.conformanceRejection.rawValue, 2)

        // A failure carries the code, so neither adapter has to re-derive it.
        XCTAssertEqual(VideoWorkflow.Failure.inputError("x").exitCode, .inputError)
        XCTAssertEqual(VideoWorkflow.Failure.conformance("x").exitCode, .conformanceRejection)
    }

    // MARK: - Probe Report

    func testProbeReportUsesTheSharedEighteenColumnLayout() throws {
        let outcome = try VideoWorkflow.probe(bitstream: h264MP4())

        XCTAssertEqual(outcome.exitCode, .success)
        XCTAssertEqual(outcome.output, """
            Container:        MP4
            Codec:            H.264/AVC
            Profile:          High
            Level:            4.1
            Resolution:       1920x1080
            Chroma:           4:2:0
            Bit depth:        8-bit
            Scan:             progressive
            Frame rate:       30.000 fps
            Frames:           300 (sampleTable)
            Transfer syntax:  1.2.840.10008.1.2.4.102
                              MPEG-4 AVC/H.264 High Profile / Level 4.1

            Conformance:      OK
            """)
    }

    /// PS3.5 8.2.5-8.2.12 permit audio, and `convert` keeps it, so the report
    /// names the tracks without calling them discarded or forbidden (D34).
    func testProbeReportNamesCarriedAudioTracks() throws {
        let outcome = try VideoWorkflow.probe(bitstream: h264MP4WithAudio())
        XCTAssertEqual(outcome.exitCode, .success)
        XCTAssertTrue(outcome.output.contains(
            "Audio tracks:     1 (carried in the bit stream; not checked against PS3.5 8.2.5/8.2.12)"),
            outcome.output)
        XCTAssertFalse(outcome.output.contains("no audio"))
        XCTAssertFalse(outcome.output.contains("discard"))
        XCTAssertEqual(outcome.exitCode, .success, "audio is not a conformance defect")
    }

    func testProbeReportHasNoAudioLineWithoutAudioTracks() throws {
        let outcome = try VideoWorkflow.probe(bitstream: h264MP4())
        XCTAssertFalse(outcome.output.contains("Audio tracks:"))
    }

    // MARK: - Default Type Notice

    /// A wrong `--type` yields a valid but mislabelled object, so defaulting is
    /// announced. Both adapters take the notice from here.
    func testDefaultTypeNoticeIsEmittedOnlyWhenTypeWasNotGiven() throws {
        let implicit = try VideoWorkflow.convert(
            bitstream: h264MP4(), type: .endoscopic, typeWasExplicit: false, dryRun: true)
        XCTAssertEqual(implicit.output, """
            note: Using SOP class Video Endoscopic Image Storage (modality ES).
                  Override with --type microscopic|photographic.
            """)

        let explicit = try VideoWorkflow.convert(
            bitstream: h264MP4(), type: .endoscopic, typeWasExplicit: true, dryRun: true)
        XCTAssertTrue(explicit.output.isEmpty,
                      "naming the type explicitly must silence the notice")
    }

    func testAudioNoteIsEmittedOnConvert() throws {
        let outcome = try VideoWorkflow.convert(
            bitstream: h264MP4WithAudio(), type: .endoscopic,
            typeWasExplicit: true, dryRun: true)
        XCTAssertEqual(outcome.output, """
            warning: input has 1 audio track, kept in the bit stream; DICOMKit does not \
            check it against PS3.5 8.2.5/8.2.12 or describe its channels in (003A,0300).
            """)
    }

    /// The payload is encapsulated unchanged, audio included (PS3.5 8.2.5-8.2.12
    /// permit it), and the Cine Module then carries Multiplexed Audio Channels
    /// Description Code Sequence (003A,0300): Type 2C, "Required if the Transfer
    /// Syntax used to encode the Multi-frame Image contains multiplexed
    /// (interleaved) audio channels", with "Zero or more Items" (PS3.3 Table C.7-13).
    func testConvertKeepsAudioAndWritesAnEmptyAudioChannelsSequence() throws {
        let input = h264MP4WithAudio()
        let outcome = try VideoWorkflow.convert(
            bitstream: input, type: .endoscopic, typeWasExplicit: true)
        let dataSet = try XCTUnwrap(outcome.video).toDataSet()

        let fragments = try XCTUnwrap(dataSet[.pixelData]?.encapsulatedFragments)
        XCTAssertEqual(fragments.count, 1)
        // A fragment is padded to even length, so compare the prefix.
        XCTAssertEqual(fragments[0].prefix(input.count), input,
                       "the audio track must not be stripped from the payload")

        let audio = try XCTUnwrap(
            dataSet[Tag(group: 0x003A, element: 0x0300)],
            "(003A,0300) is required once the bit stream carries audio")
        XCTAssertEqual(audio.vr, .SQ)
        XCTAssertEqual(audio.sequenceItems?.count ?? 0, 0)

        // The sequence survives encoding into a Part 10 file.
        let reparsed = try DICOMFile.read(from: try XCTUnwrap(outcome.data))
        XCTAssertNotNil(reparsed.dataSet[Tag(group: 0x003A, element: 0x0300)])
    }

    /// The deprecated name returns the corrected text rather than the old
    /// "DICOM video has no audio, discarding" claim.
    @available(*, deprecated)
    func testDeprecatedAudioDiscardedLineForwardsToTheCorrectedText() {
        XCTAssertEqual(VideoConsole.audioDiscardedLine(trackCount: 1),
                       VideoConsole.audioCarriedLine(trackCount: 1))
        XCTAssertFalse(VideoConsole.audioDiscardedLine(trackCount: 3).contains("no audio"))
    }

    /// Without audio the Type 2C condition is not met, so the sequence stays out.
    func testConvertWithoutAudioOmitsTheAudioChannelsSequence() throws {
        let outcome = try VideoWorkflow.convert(
            bitstream: h264MP4(), type: .endoscopic, typeWasExplicit: true)
        let dataSet = try XCTUnwrap(outcome.video).toDataSet()
        XCTAssertNil(dataSet[Tag(group: 0x003A, element: 0x0300)])
    }

    // MARK: - Conformance Rejection

    /// PS3.5 8.2.7 blesses only MP4 and MPEG-TS, so a QuickTime payload is
    /// rejected — with the remedy, and as exit 2 rather than exit 1.
    func testQuickTimeContainerIsRejectedWithItsRemedy() {
        XCTAssertThrowsError(try VideoWorkflow.planConversion(bitstream: quickTimeMOV())) {
            guard let failure = $0 as? VideoWorkflow.Failure else {
                return XCTFail("expected a VideoWorkflow.Failure, got \($0)")
            }
            XCTAssertEqual(failure.exitCode, .conformanceRejection)
            XCTAssertTrue(failure.message.contains("QuickTime (MOV) is not a permitted container"))
            XCTAssertTrue(failure.message.contains("ffmpeg -i input.mov -map 0:v:0 -map '0:a?' -c copy output.mp4"),
                          "a rejection has to carry its remedy")
        }
    }

    /// A non-video input names what was actually supplied and points at the
    /// right tool, rather than complaining about a missing start code.
    func testNonVideoInputIsRejectedByName() {
        let png = Data([0x89, 0x50, 0x4E, 0x47]) + Data(repeating: 0, count: 64)
        XCTAssertThrowsError(try VideoWorkflow.planConversion(bitstream: png)) {
            guard let failure = $0 as? VideoWorkflow.Failure else {
                return XCTFail("expected a VideoWorkflow.Failure, got \($0)")
            }
            XCTAssertEqual(failure.exitCode, .conformanceRejection)
            XCTAssertTrue(failure.message.contains("a PNG image"))
            XCTAssertTrue(failure.message.contains("dicom-image"))
        }
    }

    // MARK: - Flag Validation

    /// `--trust-input` on a transport stream cannot also auto-detect a transfer
    /// syntax, because nothing was read from the stream.
    func testTrustedTransportStreamRequiresAnExplicitTransferSyntax() {
        var ts = Data()
        for _ in 0..<10 {
            ts.append(0x47)
            ts.append(Data(repeating: 0x00, count: 187))
        }

        XCTAssertThrowsError(
            try VideoWorkflow.planConversion(bitstream: ts, trustInput: true)
        ) {
            guard let failure = $0 as? VideoWorkflow.Failure else {
                return XCTFail("expected a VideoWorkflow.Failure, got \($0)")
            }
            XCTAssertEqual(failure.exitCode, .inputError)
            XCTAssertEqual(failure.message, VideoConsole.trustInputNeedsTransferSyntaxLine)
        }

        // With one named, the same input is accepted on the caller's assertion.
        XCTAssertNoThrow(try VideoWorkflow.planConversion(
            bitstream: ts, explicitTransferSyntax: "1.2.840.10008.1.2.4.102",
            trustInput: true))
    }

    func testUnknownAndNonVideoTransferSyntaxesAreDistinguished() {
        XCTAssertThrowsError(try VideoWorkflow.planConversion(
            bitstream: h264MP4(), explicitTransferSyntax: "9.9.9")
        ) {
            XCTAssertEqual(($0 as? VideoWorkflow.Failure)?.message,
                           VideoConsole.unknownTransferSyntaxLine("9.9.9"))
        }

        // A real UID that carries still images, not video.
        XCTAssertThrowsError(try VideoWorkflow.planConversion(
            bitstream: h264MP4(), explicitTransferSyntax: "1.2.840.10008.1.2.1")
        ) {
            XCTAssertEqual(($0 as? VideoWorkflow.Failure)?.message,
                           VideoConsole.notAVideoTransferSyntaxLine("1.2.840.10008.1.2.1"))
        }
    }

    func testImplausibleFrameRateIsRejected() {
        for rate in [0.0, -5.0, 1000.0, 5000.0] {
            XCTAssertThrowsError(try VideoWorkflow.planConversion(
                bitstream: h264MP4(), frameRateOverride: rate)
            ) {
                XCTAssertEqual(($0 as? VideoWorkflow.Failure)?.exitCode, .inputError,
                               "\(rate) fps should be refused as implausible")
            }
        }

        XCTAssertNoThrow(try VideoWorkflow.planConversion(
            bitstream: h264MP4(), frameRateOverride: 25))
    }

    /// `--series-uid` names one series; `--series-mode per-file` mints one per
    /// clip. Rejecting the pair beats silently ignoring one of them.
    func testSeriesUIDCannotBeCombinedWithPerFileMode() {
        let withUID = VideoWorkflow.Metadata(seriesUID: "1.2.3")

        XCTAssertThrowsError(try VideoWorkflow.validateBatchOptions(
            seriesMode: .perFile, metadata: withUID)
        ) {
            XCTAssertEqual(($0 as? VideoWorkflow.Failure)?.message,
                           VideoConsole.seriesUIDConflictsWithPerFileLine)
        }

        // Legal in single mode, and legal in per-file mode without the UID.
        XCTAssertNoThrow(try VideoWorkflow.validateBatchOptions(
            seriesMode: .single, metadata: withUID))
        XCTAssertNoThrow(try VideoWorkflow.validateBatchOptions(
            seriesMode: .perFile, metadata: VideoWorkflow.Metadata()))
    }

    // MARK: - Frame-Rate Override

    /// The override has to reach the built object's Cine attributes, or the
    /// flag would validate and then do nothing.
    func testFrameRateOverrideReachesTheCineAttributes() throws {
        let outcome = try VideoWorkflow.convert(
            bitstream: h264MP4(), type: .endoscopic, typeWasExplicit: true,
            frameRateOverride: 25)

        let dataSet = try XCTUnwrap(outcome.video).toDataSet()
        // 1000 ms / 25 fps = 40 ms per frame.
        XCTAssertEqual(dataSet[.frameTime]?.stringValue, "40")
        XCTAssertEqual(dataSet[.cineRate]?.stringValue, "25")
        XCTAssertEqual(dataSet[.recommendedDisplayFrameRate]?.stringValue, "25")
    }

    // MARK: - Metadata

    /// Every `--patient-*` / study / series flag the form and the CLI expose has
    /// to land in the data set, or the two surfaces would appear to accept
    /// values they then drop.
    func testEveryMetadataFieldReachesTheDataSet() throws {
        let metadata = VideoWorkflow.Metadata(
            patientName: "Doe^Jane",
            patientID: "P123",
            patientBirthDate: "19800101",
            patientSex: "F",
            studyUID: "1.2.3.4",
            seriesUID: "1.2.3.5",
            accessionNumber: "A99",
            studyID: "S1",
            referringPhysician: "Ref^Dr",
            seriesDescription: "Endoscopy clip",
            modality: "ES",
            manufacturer: "Acme",
            institutionName: "General Hospital"
        )

        let outcome = try VideoWorkflow.convert(
            bitstream: h264MP4(), type: .photographic, typeWasExplicit: true,
            metadata: metadata, seriesNumber: 3, instanceNumber: 7)

        let dataSet = try XCTUnwrap(outcome.video).toDataSet()
        XCTAssertEqual(dataSet[.patientName]?.stringValue, "Doe^Jane")
        XCTAssertEqual(dataSet[.patientID]?.stringValue, "P123")
        XCTAssertEqual(dataSet[.patientBirthDate]?.stringValue, "19800101")
        XCTAssertEqual(dataSet[.patientSex]?.stringValue, "F")
        XCTAssertEqual(dataSet[.studyInstanceUID]?.stringValue, "1.2.3.4")
        XCTAssertEqual(dataSet[.seriesInstanceUID]?.stringValue, "1.2.3.5")
        XCTAssertEqual(dataSet[.accessionNumber]?.stringValue, "A99")
        XCTAssertEqual(dataSet[.studyID]?.stringValue, "S1")
        XCTAssertEqual(dataSet[.referringPhysicianName]?.stringValue, "Ref^Dr")
        XCTAssertEqual(dataSet[.seriesDescription]?.stringValue, "Endoscopy clip")
        XCTAssertEqual(dataSet[.manufacturer]?.stringValue, "Acme")
        XCTAssertEqual(dataSet[.institutionName]?.stringValue, "General Hospital")
        XCTAssertEqual(dataSet[.seriesNumber]?.stringValue, "3")
        XCTAssertEqual(dataSet[.instanceNumber]?.stringValue, "7")
    }

    /// `--type` selects the SOP class, and the modality follows from it unless
    /// `--modality` overrides it.
    func testTypeSelectsTheSOPClassAndItsDefaultModality() throws {
        let expected: [(VideoConsole.TypeArgument, String)] = [
            (.endoscopic, "ES"), (.microscopic, "GM"), (.photographic, "XC"),
        ]

        for (type, modality) in expected {
            let outcome = try VideoWorkflow.convert(
                bitstream: h264MP4(), type: type, typeWasExplicit: true)
            let video = try XCTUnwrap(outcome.video)
            XCTAssertEqual(video.sopClassUID, type.videoType.sopClassUID)
            XCTAssertEqual(video.toDataSet()[.modality]?.stringValue, modality)
        }

        // An explicit --modality wins over the type's default.
        let overridden = try VideoWorkflow.convert(
            bitstream: h264MP4(), type: .endoscopic, typeWasExplicit: true,
            metadata: VideoWorkflow.Metadata(modality: "OT"))
        XCTAssertEqual(try XCTUnwrap(overridden.video)
            .toDataSet()[.modality]?.stringValue, "OT")
    }

    // MARK: - Dry Run

    /// `--dry-run` validates and reports but must build nothing.
    func testDryRunProducesNoBytes() throws {
        let outcome = try VideoWorkflow.convert(
            bitstream: h264MP4(), type: .endoscopic, typeWasExplicit: true, dryRun: true)
        XCTAssertNil(outcome.data)
        XCTAssertNil(outcome.video)
        XCTAssertEqual(outcome.plan.transferSyntax.uid, "1.2.840.10008.1.2.4.102")
    }

    // MARK: - Round Trip

    /// The whole point of remuxing: the bytes that go in come back out. Both
    /// surfaces run this same encode/extract pair.
    func testConvertExtractRoundTripIsByteIdentical() throws {
        let original = h264MP4()

        let outcome = try VideoWorkflow.convert(
            bitstream: original, type: .endoscopic, typeWasExplicit: true)
        let encoded = try XCTUnwrap(outcome.data)

        let extracted = try VideoWorkflow.extract(fileData: encoded, inputPath: "clip.dcm")
        XCTAssertEqual(extracted.bitstream, original,
                       "remuxing must preserve the camera's pixel data bit-for-bit")
        XCTAssertEqual(extracted.container, .mp4)
        XCTAssertEqual(extracted.codec, .h264)
        XCTAssertEqual(extracted.transferSyntax.uid, "1.2.840.10008.1.2.4.102")
        XCTAssertEqual(extracted.suggestedFileExtension, "mp4")
    }

    /// The payload keeps the container it was encapsulated with, so a mismatched
    /// output extension is worth a warning — and a matching one is not.
    func testExtensionWarningFollowsTheContainerNotTheCodec() throws {
        let outcome = try VideoWorkflow.convert(
            bitstream: h264MP4(), type: .endoscopic, typeWasExplicit: true)
        let extracted = try VideoWorkflow.extract(
            fileData: try XCTUnwrap(outcome.data), inputPath: "clip.dcm")

        XCTAssertNil(VideoWorkflow.extensionWarning(for: extracted, outputPath: "out.mp4"))
        XCTAssertNil(VideoWorkflow.extensionWarning(for: extracted, outputPath: "out"),
                     "no extension is a deliberate choice, not a mistake")
        XCTAssertEqual(
            VideoWorkflow.extensionWarning(for: extracted, outputPath: "out.264"),
            "warning: payload is MP4; '.mp4' would suit it better than '.264'.")
    }

    /// A mislabelled object — one whose payload contradicts the transfer syntax it
    /// declares — is extracted unchanged but no longer silently. Without the
    /// warning the defect surfaces against whatever reads the payload next rather
    /// than against the object that caused it.
    func testExtractWarnsWhenPayloadContradictsTheDeclaredTransferSyntax() throws {
        let outcome = try VideoWorkflow.convert(
            bitstream: h264MP4(), type: .endoscopic, typeWasExplicit: true)
        let object = try XCTUnwrap(outcome.data)

        // Demote the SPS to Main Profile in place, which is exactly the shape of
        // the third-party objects this warning exists for: the declared
        // transfer syntax still says High, while the bit stream no longer does.
        let sps = Self.spsH264Unit
        let range = try XCTUnwrap(object.range(of: sps))
        var mislabelled = object
        // spsH264Unit is [NAL header, profile_idc, ...], so the profile byte is
        // the one after the 0x67 header.
        mislabelled[range.lowerBound + 1] = 77

        let extracted = try VideoWorkflow.extract(
            fileData: mislabelled, inputPath: "mislabelled.dcm")

        XCTAssertEqual(
            extracted.bitstream.count,
            try VideoWorkflow.extract(
                fileData: object, inputPath: "clip.dcm").bitstream.count,
            "the payload is still carried out unchanged")

        let warning = try XCTUnwrap(
            VideoWorkflow.conformanceWarning(for: extracted),
            "a payload contradicting its transfer syntax must not pass silently")
        XCTAssertTrue(warning.hasPrefix("warning: "))
        XCTAssertTrue(warning.contains("1.2.840.10008.1.2.4.102"))
        XCTAssertTrue(warning.contains("profile_idc 77"))
    }

    /// The warning is for contradictions only: a conformant object must not
    /// acquire a scary line on a path whose whole purpose is faithful recovery.
    func testExtractIsSilentWhenThePayloadMatchesItsTransferSyntax() throws {
        let outcome = try VideoWorkflow.convert(
            bitstream: h264MP4(), type: .endoscopic, typeWasExplicit: true)
        let extracted = try VideoWorkflow.extract(
            fileData: try XCTUnwrap(outcome.data), inputPath: "clip.dcm")

        XCTAssertNil(VideoWorkflow.conformanceWarning(for: extracted))
    }

    /// Every video transfer syntax is encapsulated (PS3.5 A.4), and the
    /// non-fragmentable ones want the whole stream in one fragment. The Basic
    /// Offset Table is present but empty: A.4 allows a non-empty one only with
    /// an offset per frame, which an inter-coded stream does not have.
    func testPixelDataIsEncapsulatedInASingleFragment() throws {
        let outcome = try VideoWorkflow.convert(
            bitstream: h264MP4(), type: .endoscopic, typeWasExplicit: true)
        let element = try XCTUnwrap(try XCTUnwrap(outcome.video).toDataSet()[.pixelData])

        XCTAssertEqual(element.length, 0xFFFF_FFFF, "encapsulated, not a native OB value")
        XCTAssertEqual(element.encapsulatedFragments?.count, 1)
        // PS3.5 8.2.5 / 8.2.6: "The Basic Offset Table shall be empty (present but zero length)".
        XCTAssertEqual(element.encapsulatedOffsetTable, [])
    }

    // MARK: - Batch

    /// Clips sort naturally, so clip2 precedes clip10 — which a lexicographic
    /// sort gets backwards, and which decides InstanceNumber order.
    func testBatchOrdersClipsNaturally() {
        let names = ["clip10.mp4", "clip2.mp4", "clip1.mp4"]
        XCTAssertEqual(names.sorted(by: naturalCompare),
                       ["clip1.mp4", "clip2.mp4", "clip10.mp4"])
    }

    /// Single mode: one series, InstanceNumber counting up across the clips.
    func testBatchSingleModeSharesOneSeriesAndNumbersInstances() throws {
        let clip = h264MP4()
        let inputs = [URL(fileURLWithPath: "/tmp/a.mp4"),
                      URL(fileURLWithPath: "/tmp/b.mp4"),
                      URL(fileURLWithPath: "/tmp/c.mp4")]
        var written: [Data] = []

        let outcome = VideoWorkflow.runBatch(
            inputs: inputs, type: .endoscopic, typeWasExplicit: true,
            seriesMode: .single,
            readFile: { _ in clip },
            writeFile: { item in
                written.append(item.data ?? Data())
                return "/out/" + item.outputName
            }
        )

        XCTAssertEqual(outcome.exitCode, .success)
        XCTAssertEqual(written.count, 3)

        let sets = try written.map { try DICOMFile.read(from: $0).dataSet }
        let seriesUIDs = Set(sets.map { $0[.seriesInstanceUID]?.stringValue ?? "" })
        XCTAssertEqual(seriesUIDs.count, 1, "single mode puts every clip in one series")
        XCTAssertEqual(sets.map { $0[.instanceNumber]?.stringValue }, ["1", "2", "3"])
        XCTAssertEqual(sets.map { $0[.seriesNumber]?.stringValue }, ["1", "1", "1"])

        // A batch is one patient visit, so the Study UID is shared in both modes.
        XCTAssertEqual(Set(sets.map { $0[.studyInstanceUID]?.stringValue ?? "" }).count, 1)
    }

    /// Per-file mode: a fresh series each, InstanceNumber restarting at 1.
    func testBatchPerFileModeGivesEachClipItsOwnSeries() throws {
        let clip = h264MP4()
        let inputs = [URL(fileURLWithPath: "/tmp/a.mp4"),
                      URL(fileURLWithPath: "/tmp/b.mp4")]
        var written: [Data] = []

        let outcome = VideoWorkflow.runBatch(
            inputs: inputs, type: .endoscopic, typeWasExplicit: true,
            seriesMode: .perFile,
            readFile: { _ in clip },
            writeFile: { item in
                written.append(item.data ?? Data())
                return "/out/" + item.outputName
            }
        )

        XCTAssertEqual(outcome.exitCode, .success)
        let sets = try written.map { try DICOMFile.read(from: $0).dataSet }
        XCTAssertEqual(Set(sets.map { $0[.seriesInstanceUID]?.stringValue ?? "" }).count, 2)
        XCTAssertEqual(sets.map { $0[.instanceNumber]?.stringValue }, ["1", "1"])
        XCTAssertEqual(sets.map { $0[.seriesNumber]?.stringValue }, ["1", "2"])
        XCTAssertEqual(Set(sets.map { $0[.studyInstanceUID]?.stringValue ?? "" }).count, 1)
    }

    /// Fail-fast is the default, so a half-populated series is never left behind.
    func testBatchStopsAtTheFirstFailureUnlessToldToContinue() {
        let good = h264MP4()
        let bad = quickTimeMOV()
        let inputs = [URL(fileURLWithPath: "/tmp/1_good.mp4"),
                      URL(fileURLWithPath: "/tmp/2_bad.mov"),
                      URL(fileURLWithPath: "/tmp/3_good.mp4")]
        func payload(_ url: URL) -> Data? {
            url.lastPathComponent.hasSuffix(".mov") ? bad : good
        }

        var writes = 0
        let stopped = VideoWorkflow.runBatch(
            inputs: inputs, type: .endoscopic, typeWasExplicit: true,
            continueOnError: false,
            readFile: payload,
            writeFile: { item in writes += 1; return "/out/" + item.outputName }
        )
        XCTAssertEqual(stopped.exitCode, .conformanceRejection)
        XCTAssertEqual(writes, 1, "the clip after the failure must not be written")
        // The stop report is commentary, so it goes to the diagnostics stream.
        XCTAssertTrue(stopped.diagnostics.contains(
            "Stopped at '2_bad.mov'. 1 file(s) already written."))
        // The clip that did succeed is still a result worth capturing.
        XCTAssertTrue(stopped.output.contains("1_good.mp4 -> 1_good.dcm"))

        writes = 0
        let continued = VideoWorkflow.runBatch(
            inputs: inputs, type: .endoscopic, typeWasExplicit: true,
            continueOnError: true,
            readFile: payload,
            writeFile: { item in writes += 1; return "/out/" + item.outputName }
        )
        // Still exit 2 — clips were skipped — but the rest were converted.
        XCTAssertEqual(continued.exitCode, .conformanceRejection)
        XCTAssertEqual(writes, 2)
        XCTAssertTrue(continued.output.contains("Converted 2 of 3 clips (1 skipped)."))
        XCTAssertTrue(continued.output.contains("skipped: 2_bad.mov —"))
    }

    /// A skipped clip must not leave a gap in InstanceNumber: numbering follows
    /// successful conversions, not the position in the input list.
    func testBatchNumberingSkipsNoIndicesWhenAClipFails() throws {
        let good = h264MP4()
        let bad = quickTimeMOV()
        let inputs = [URL(fileURLWithPath: "/tmp/1_good.mp4"),
                      URL(fileURLWithPath: "/tmp/2_bad.mov"),
                      URL(fileURLWithPath: "/tmp/3_good.mp4")]
        var written: [Data] = []

        _ = VideoWorkflow.runBatch(
            inputs: inputs, type: .endoscopic, typeWasExplicit: true,
            continueOnError: true,
            readFile: { $0.lastPathComponent.hasSuffix(".mov") ? bad : good },
            writeFile: { item in
                written.append(item.data ?? Data())
                return "/out/" + item.outputName
            }
        )

        let sets = try written.map { try DICOMFile.read(from: $0).dataSet }
        XCTAssertEqual(sets.map { $0[.instanceNumber]?.stringValue }, ["1", "2"],
                       "the failure between them must not consume an InstanceNumber")
    }

    /// Results and commentary go to different streams, so
    /// `dicom-video batch … > list.txt` captures the per-clip lines and the
    /// summary without the notices mixed in. Folding both into one string is
    /// exactly the regression this pins.
    func testBatchKeepsResultsAndCommentaryOnSeparateStreams() {
        let outcome = VideoWorkflow.runBatch(
            inputs: [URL(fileURLWithPath: "/tmp/clip.mp4")],
            type: .endoscopic, typeWasExplicit: false, dryRun: true,
            readFile: { _ in h264MP4() },
            writeFile: { _ in "/out/clip.dcm" }
        )

        // The default-type notice is commentary…
        XCTAssertTrue(outcome.diagnostics.hasPrefix("note: Using SOP class"))
        XCTAssertFalse(outcome.output.contains("note:"),
                       "the notice must not land in the captured result list")
        // …and the clip line plus summary are the result.
        XCTAssertTrue(outcome.output.contains("clip.mp4: OK"))
        XCTAssertTrue(outcome.output.contains("Converted 1 of 1 clips."))

        // A single-console surface shows them together, commentary first.
        XCTAssertEqual(outcome.combined, outcome.diagnostics + "\n" + outcome.output)
    }

    /// The fail-fast stop report is commentary too, and carries exactly one
    /// blank line between the error and the "Stopped at" line.
    func testBatchStopReportIsCommentaryWithOneBlankSeparator() {
        let outcome = VideoWorkflow.runBatch(
            inputs: [URL(fileURLWithPath: "/tmp/bad.mov")],
            type: .endoscopic, typeWasExplicit: true,
            readFile: { _ in quickTimeMOV() },
            writeFile: { _ in "/out/bad.dcm" }
        )

        XCTAssertTrue(outcome.output.isEmpty,
                      "nothing was converted, so there is no result to capture")
        XCTAssertTrue(outcome.diagnostics.contains(
            "-c copy output.mp4\n\nStopped at 'bad.mov'. 0 file(s) already written."),
            "one blank line separates the remedy from the stop report, not two")
    }

    // MARK: - Output Path Resolution

    /// A folder picker hands back a directory, and people type one. Writing to it
    /// literally makes the destination collide with the folder itself, so a clip
    /// that converts perfectly cannot be saved — the failure people actually hit.
    func testOutputDirectoryBecomesAFileInsideIt() {
        let resolved = VideoWorkflow.resolveOutputURL(
            output: "/Users/me/Desktop/Test",
            input: URL(fileURLWithPath: "/Users/me/Desktop/IMG_0429.MOV"),
            fileExtension: "dcm",
            isDirectory: { $0 == "/Users/me/Desktop/Test" })

        XCTAssertTrue(resolved.redirectedIntoDirectory)
        XCTAssertEqual(resolved.url.path, "/Users/me/Desktop/Test/IMG_0429.dcm",
                       "the object lands in the chosen folder, named after the clip")
    }

    /// The common case must not be disturbed: an explicit filename is obeyed
    /// exactly, extension and all.
    func testExplicitOutputFileIsUsedVerbatim() {
        let resolved = VideoWorkflow.resolveOutputURL(
            output: "/Users/me/out/clip.dcm",
            input: URL(fileURLWithPath: "/Users/me/IMG_0429.MOV"),
            fileExtension: "dcm",
            isDirectory: { _ in false })

        XCTAssertFalse(resolved.redirectedIntoDirectory)
        XCTAssertEqual(resolved.url.path, "/Users/me/out/clip.dcm")
    }

    /// A path that does not exist yet is a file to create, not a folder to fill.
    func testNonExistentOutputPathIsTreatedAsAFile() {
        let resolved = VideoWorkflow.resolveOutputURL(
            output: "/Users/me/Desktop/new-name.dcm",
            input: URL(fileURLWithPath: "/Users/me/IMG_0429.MOV"),
            fileExtension: "dcm",
            isDirectory: { _ in false })

        XCTAssertFalse(resolved.redirectedIntoDirectory)
        XCTAssertEqual(resolved.url.lastPathComponent, "new-name.dcm")
    }

    /// Extraction names the file for the container actually recovered, so a
    /// payload that is really MP4 does not land under a misleading extension.
    func testExtractIntoADirectoryUsesThePayloadsExtension() {
        let resolved = VideoWorkflow.resolveOutputURL(
            output: "/Users/me/Desktop/Out",
            input: URL(fileURLWithPath: "/Users/me/clip.dcm"),
            fileExtension: "mp4",
            isDirectory: { $0 == "/Users/me/Desktop/Out" })

        XCTAssertEqual(resolved.url.path, "/Users/me/Desktop/Out/clip.mp4")
    }

    /// A trailing slash is how a folder is usually typed; it must not produce an
    /// empty name or a doubled separator.
    func testOutputDirectoryWithTrailingSlash() {
        let resolved = VideoWorkflow.resolveOutputURL(
            output: "/Users/me/Desktop/Test/",
            input: URL(fileURLWithPath: "/Users/me/IMG_0429.MOV"),
            fileExtension: "dcm",
            isDirectory: { _ in true })

        XCTAssertEqual(resolved.url.path, "/Users/me/Desktop/Test/IMG_0429.dcm")
    }

    /// A dry-run batch reports per clip and writes nothing.
    func testBatchDryRunWritesNothing() {
        let clip = h264MP4()
        var writes = 0

        let outcome = VideoWorkflow.runBatch(
            inputs: [URL(fileURLWithPath: "/tmp/a.mp4"), URL(fileURLWithPath: "/tmp/b.mp4")],
            type: .endoscopic, typeWasExplicit: true, dryRun: true,
            readFile: { _ in clip },
            writeFile: { item in writes += 1; return "/out/" + item.outputName }
        )

        XCTAssertEqual(writes, 0)
        XCTAssertEqual(outcome.exitCode, .success)
        XCTAssertTrue(outcome.output.contains("a.mp4: OK (1.2.840.10008.1.2.4.102)"))
        XCTAssertTrue(outcome.output.contains("Converted 2 of 2 clips."))
    }

    /// An unreadable clip is a per-clip failure, not a crash.
    func testBatchReportsAnUnreadableClip() {
        let outcome = VideoWorkflow.runBatch(
            inputs: [URL(fileURLWithPath: "/tmp/missing.mp4")],
            type: .endoscopic, typeWasExplicit: true, continueOnError: true,
            readFile: { _ in nil },
            writeFile: { _ in "/out/x.dcm" }
        )
        XCTAssertEqual(outcome.exitCode, .conformanceRejection)
        XCTAssertTrue(outcome.output.contains("skipped: missing.mp4 — cannot read the file"))
    }

    /// The per-clip line names where the file actually landed, so a sandbox
    /// redirect in the app shows the real destination rather than the typed one.
    func testBatchLineNamesTheActualDestination() {
        let outcome = VideoWorkflow.runBatch(
            inputs: [URL(fileURLWithPath: "/tmp/clip.mp4")],
            type: .endoscopic, typeWasExplicit: true,
            readFile: { _ in h264MP4() },
            writeFile: { _ in "/redirected/elsewhere.dcm" }
        )
        XCTAssertTrue(outcome.output.contains("clip.mp4 -> elsewhere.dcm"))
    }

    // MARK: - Discovery

    /// Extension filtering is a first pass only — content is sniffed afterwards.
    func testCandidateExtensionsCoverTheThreeCodecsAndBothContainers() {
        for ext in ["mp4", "m4v", "mov", "ts", "m2ts", "mts",
                    "264", "h264", "265", "hevc", "h265", "m2v", "mpv", "mpg", "mpeg"] {
            XCTAssertTrue(VideoWorkflow.videoExtensions.contains(ext),
                          "\(ext) should be worth attempting")
        }
        XCTAssertFalse(VideoWorkflow.videoExtensions.contains("dcm"))
        XCTAssertFalse(VideoWorkflow.videoExtensions.contains("png"))
    }

    // MARK: - Shared Text

    /// The lines both adapters print, pinned so an edit has to be deliberate.
    func testSharedLinesKeepTheirCLICanonicalWording() {
        XCTAssertEqual(VideoConsole.cannotReadLine("clip.mp4"),
                       "error: cannot read 'clip.mp4'.")
        XCTAssertEqual(VideoConsole.outputExistsLine("out.dcm"),
                       "error: 'out.dcm' already exists. Pass --force to overwrite.")
        XCTAssertEqual(VideoConsole.notReadableDICOMLine("x.dcm"),
                       "error: 'x.dcm' is not a readable DICOM file.")
        XCTAssertEqual(VideoConsole.notADirectoryLine("clips"),
                       "error: 'clips' is not a directory.")
        XCTAssertEqual(VideoConsole.noVideoFilesLine("clips"),
                       "error: no video files found in 'clips'.")
        XCTAssertEqual(VideoConsole.wroteLine("out.dcm"), "Wrote out.dcm")
        XCTAssertEqual(VideoConsole.extractedLine(path: "clip.mp4", byteCount: 376),
                       "Wrote clip.mp4 (376 bytes)")
        XCTAssertEqual(VideoConsole.dryRunTrailer,
                       "\nDry run: conformant, nothing written.")
        XCTAssertEqual(VideoConsole.conformanceOKLine, "\nConformance:      OK")
        XCTAssertEqual(VideoConsole.batchConvertedLine(input: "a.mp4", output: "a.dcm"),
                       "a.mp4 -> a.dcm")
        XCTAssertEqual(VideoConsole.audioCarriedLine(trackCount: 2), """
            warning: input has 2 audio tracks, kept in the bit stream; DICOMKit does not \
            check them against PS3.5 8.2.5/8.2.12 or describe their channels in (003A,0300).
            """)
        XCTAssertEqual(
            VideoConsole.audioCarriedLine([AudioStreamInfo(format: .aac, sampleRate: 48_000, channels: 2)]),
            "note: carrying 1 audio track (AAC, 48 kHz, 2 ch) inside the encapsulated bit stream, "
                + "as PS3.5 8.2.5 and 8.2.12 permit.")
    }

    /// A rejection is only actionable if it names the constraint and the fix.
    func testViolationReportCarriesMessageThenRemedy() {
        let violation = VideoConformanceViolation.chromaFormatNotPermitted(observed: "4:2:2")
        XCTAssertEqual(VideoConsole.violationReport(violation), """
            error: chroma format 4:2:2 is not permitted; DICOM video requires 4:2:0 (PS3.5 8.2.7)

                   ffmpeg -i input.mp4 -c:v libx264 -pix_fmt yuv420p fixed.mp4
            """)
    }

    /// The Workshop form parses its own values, so it reproduces the two lines
    /// ArgumentParser would have printed for an unusable one.
    func testInvalidValueLinesMatchArgumentParsersShape() {
        XCTAssertEqual(
            VideoConsole.invalidValueLines(
                value: "fast", option: "--frame-rate", help: VideoConsole.Help.frameRate),
            ["Error: The value 'fast' is invalid for '--frame-rate <frame-rate>'",
             "Help:  --frame-rate <frame-rate>  Override the probed frame rate (validated)"])
    }

    /// The argument enums' raw values are the contract both surfaces spell out.
    func testArgumentEnumRawValuesAreStable() {
        XCTAssertEqual(VideoConsole.TypeArgument.allCases.map(\.rawValue),
                       ["endoscopic", "microscopic", "photographic"])
        XCTAssertEqual(VideoConsole.SeriesMode.allCases.map(\.rawValue),
                       ["single", "per-file"])
    }

    // MARK: - Verbose

    /// `--verbose` is commentary, never a result: it must not disturb a single
    /// character of what a script reading stdout sees. This is the property the
    /// whole two-stream split exists to protect.
    func testVerboseLeavesTheProbeReportOnStdoutUntouched() throws {
        let quiet = try VideoWorkflow.probe(bitstream: h264MP4())
        let loud = try VideoWorkflow.probe(bitstream: h264MP4(), verbose: true)

        XCTAssertEqual(loud.output, quiet.output,
                       "the report is the result; verbose belongs in diagnostics")
        XCTAssertEqual(loud.exitCode, quiet.exitCode)
        XCTAssertTrue(quiet.diagnostics.isEmpty,
                      "a run that did not ask for verbose says nothing extra")
    }

    /// Every verbose line carries the prefix, so a reader (and a grep) can tell
    /// commentary from the report it accompanies.
    func testVerboseLinesAreAllPrefixed() throws {
        let outcome = try VideoWorkflow.probe(bitstream: h264MP4(), verbose: true)
        XCTAssertFalse(outcome.diagnostics.isEmpty)
        for line in outcome.diagnostics.split(separator: "\n") {
            XCTAssertTrue(line.hasPrefix("verbose: "), "unprefixed verbose line: \(line)")
        }
    }

    /// The three decisions a probe makes silently, now said out loud.
    func testProbeVerboseNamesContainerFrameCountAndSyntaxChoice() throws {
        let bitstream = h264MP4()
        let outcome = try VideoWorkflow.probe(bitstream: bitstream, verbose: true)

        XCTAssertEqual(outcome.diagnostics, """
            verbose: read \(bitstream.count) bytes; container detected as MP4
            verbose: frame count 300 from sampleTable
            verbose: transfer syntax 1.2.840.10008.1.2.4.102 selected from the \
            bitstream's codec, profile and level
            """)
    }

    /// `probe` prints its own conformance verdict, so its commentary must not
    /// pre-empt it with a "conformant" claim of its own.
    func testProbeVerboseDoesNotPreEmptTheConformanceVerdict() throws {
        let outcome = try VideoWorkflow.probe(bitstream: h264MP4(), verbose: true)
        XCTAssertFalse(outcome.diagnostics.contains("conformant"),
                       "the verdict is the report's to give, not the commentary's")
        XCTAssertTrue(outcome.output.contains("Conformance:      OK"))
    }

    /// A conversion says which UIDs it minted and that the payload was carried
    /// through byte-for-byte — the two things a remux is judged on.
    func testConvertVerboseReportsIdentityAndByteAccounting() throws {
        let bitstream = h264MP4()
        let outcome = try VideoWorkflow.convert(
            bitstream: bitstream, type: .endoscopic, typeWasExplicit: true, verbose: true)

        let data = try XCTUnwrap(outcome.data)
        let video = try XCTUnwrap(outcome.video)
        XCTAssertTrue(outcome.output.contains(
            "verbose: SOP class Video Endoscopic Image Storage"))
        XCTAssertTrue(outcome.output.contains(
            "verbose: Study Instance UID  \(video.studyInstanceUID) (generated)"))
        XCTAssertTrue(outcome.output.contains(
            "verbose: SOP Instance UID    \(video.sopInstanceUID) (generated)"))
        XCTAssertTrue(outcome.output.contains(
            "verbose: encoded \(data.count) bytes: \(bitstream.count) bytes of "
            + "bitstream carried unchanged, \(data.count - bitstream.count) bytes "
            + "of DICOM overhead"),
            "the byte accounting is what shows the pixels were not re-encoded")
    }

    /// A UID the caller supplied is reported as given, not as generated — the
    /// distinction matters when a clip lands in the wrong study.
    func testConvertVerboseDistinguishesGivenUIDsFromGeneratedOnes() throws {
        let outcome = try VideoWorkflow.convert(
            bitstream: h264MP4(), type: .endoscopic, typeWasExplicit: true, verbose: true,
            metadata: VideoWorkflow.Metadata(studyUID: "1.2.3.4"))

        XCTAssertTrue(outcome.output.contains(
            "verbose: Study Instance UID  1.2.3.4 (given)"))
        XCTAssertTrue(outcome.output.contains("Series Instance UID"))
        XCTAssertTrue(outcome.output.contains("(generated)"),
                      "the series UID was not supplied, so it is minted")
    }

    /// An override silently replaces what the bitstream declared, so verbose
    /// names both values.
    func testConvertVerboseNamesBothSidesOfAFrameRateOverride() throws {
        let outcome = try VideoWorkflow.convert(
            bitstream: h264MP4(), type: .endoscopic, typeWasExplicit: true,
            frameRateOverride: 25, dryRun: true, verbose: true)

        XCTAssertTrue(outcome.output.contains(
            "verbose: frame rate overridden: 30.000 fps -> 25.000 fps"))
    }

    /// A trusted transport stream is the one path where nothing is validated,
    /// so verbose has to say so rather than implying a check happened.
    func testVerboseSaysWhenATrustedStreamWasNotValidated() {
        let lines = VideoConsole.verboseTransferSyntaxLines(
            .mpeg2MainProfile, wasExplicit: true, trusted: true)
        XCTAssertEqual(lines, ["transfer syntax 1.2.840.10008.1.2.4.100 taken on trust "
                               + "(--trust-input); the stream was not validated"])
        XCTAssertFalse(lines.contains { $0.contains("conformant") })
    }

    /// A rejection is where "what did you read?" matters most, so the lines
    /// gathered before the throw are handed back rather than dropped.
    func testRejectionStillDeliversTheCommentaryGatheredBeforeIt() {
        var delivered: [String] = []
        XCTAssertThrowsError(try VideoWorkflow.planConversion(
            bitstream: quickTimeMOV(),
            verboseSink: { delivered = $0 }
        ))
        XCTAssertEqual(delivered.count, 1)
        XCTAssertTrue(delivered[0].contains("container detected as QuickTime (MOV)"),
                      "the rejected container is the fact the user needs")
    }

    /// The wrapper keeps the message and exit code identical to the plain
    /// failure, so asking for verbose can never change a script's outcome.
    func testVerboseFailureCarriesTheSameMessageAndExitCode() {
        var thrown: Error?
        XCTAssertThrowsError(try VideoWorkflow.convert(
            bitstream: quickTimeMOV(), type: .endoscopic,
            typeWasExplicit: true, verbose: true
        )) { thrown = $0 }

        let verboseFailure = try? XCTUnwrap(thrown as? VideoWorkflow.VerboseFailure)
        let plain = VideoWorkflow.Failure.conformance(VideoConsole.violationReport(
            .containerNotPermitted(observed: "QuickTime (MOV)")))
        XCTAssertEqual(verboseFailure?.failure.message, plain.message)
        XCTAssertEqual(verboseFailure?.exitCode, .conformanceRejection)
        XCTAssertTrue(verboseFailure?.combinedMessage.hasSuffix(plain.message) ?? false,
                      "commentary precedes the rejection it explains")
    }

    /// Without verbose the ordinary `catch let failure as Failure` in both
    /// adapters must still be the one that fires.
    func testWithoutVerboseAPlainFailureIsThrown() {
        XCTAssertThrowsError(try VideoWorkflow.convert(
            bitstream: quickTimeMOV(), type: .endoscopic, typeWasExplicit: true
        )) { error in
            XCTAssertTrue(error is VideoWorkflow.Failure,
                          "a non-verbose run throws exactly what it always threw")
        }
    }

    /// Batch verbose explains the grouping and the numbering each clip got,
    /// which is what a reader checks when a series comes out wrong.
    func testBatchVerboseExplainsGroupingAndPerClipNumbering() throws {
        let clip = h264MP4()
        let inputs = [URL(fileURLWithPath: "/clips/clip1.mp4"),
                      URL(fileURLWithPath: "/clips/clip2.mp4")]

        let outcome = VideoWorkflow.runBatch(
            inputs: inputs, type: .endoscopic, typeWasExplicit: true,
            verbose: true, recursive: true,
            readFile: { _ in clip }, writeFile: { $0.outputName }
        )

        XCTAssertTrue(outcome.diagnostics.contains(
            "verbose: found 2 candidate files (searched subdirectories)"))
        XCTAssertTrue(outcome.diagnostics.contains(
            "verbose: series mode single: one series for all of them"))
        XCTAssertTrue(outcome.diagnostics.contains(
            "verbose: clip1.mp4: series 1, instance 1, 1.2.840.10008.1.2.4.102"))
        XCTAssertTrue(outcome.diagnostics.contains(
            "verbose: clip2.mp4: series 1, instance 2, 1.2.840.10008.1.2.4.102"))

        // The per-clip list on stdout is untouched by any of it.
        XCTAssertTrue(outcome.output.contains("clip1.mp4 -> clip1.dcm"))
        XCTAssertFalse(outcome.output.contains("verbose:"))
    }

    /// per-file mode mints a series per clip, and verbose is where that becomes
    /// visible without re-reading the objects.
    func testBatchVerboseShowsPerFileSeriesNumbering() throws {
        let clip = h264MP4()
        let outcome = VideoWorkflow.runBatch(
            inputs: [URL(fileURLWithPath: "/a.mp4"), URL(fileURLWithPath: "/b.mp4")],
            type: .endoscopic, typeWasExplicit: true, seriesMode: .perFile,
            verbose: true, readFile: { _ in clip }, writeFile: { $0.outputName }
        )

        XCTAssertTrue(outcome.diagnostics.contains(
            "verbose: series mode per-file: a new series per clip"))
        XCTAssertTrue(outcome.diagnostics.contains("verbose: a.mp4: series 1, instance 1"))
        XCTAssertTrue(outcome.diagnostics.contains("verbose: b.mp4: series 2, instance 1"))
    }

    /// A batch run without verbose emits no commentary beyond what it always did.
    func testBatchWithoutVerboseKeepsItsDiagnosticsUnchanged() {
        let clip = h264MP4()
        let outcome = VideoWorkflow.runBatch(
            inputs: [URL(fileURLWithPath: "/a.mp4")],
            type: .endoscopic, typeWasExplicit: true,
            readFile: { _ in clip }, writeFile: { $0.outputName }
        )
        XCTAssertFalse(outcome.diagnostics.contains("verbose:"))
    }

    /// Extract's commentary names the fragmentation, which is the one thing the
    /// summary cannot show.
    func testExtractVerboseNamesFragmentCountAndDetectedContainer() throws {
        let outcome = try VideoWorkflow.convert(
            bitstream: h264MP4(), type: .endoscopic, typeWasExplicit: true)
        let extracted = try VideoWorkflow.extract(
            fileData: try XCTUnwrap(outcome.data), inputPath: "clip.dcm")

        XCTAssertEqual(VideoConsole.verboseExtractLines(extracted), [
            "payload recovered from \(extracted.fragmentCount) "
            + "fragment\(extracted.fragmentCount == 1 ? "" : "s")",
            "container detected from the payload's own bytes as MP4",
        ])
    }

    /// The help string is single-sourced, so the CLI's `--help` row and the
    /// Workshop's toggle description cannot drift.
    func testVerboseHelpTextIsShared() {
        XCTAssertEqual(VideoConsole.Help.verbose, "Show the reasoning behind each step")
    }
}
