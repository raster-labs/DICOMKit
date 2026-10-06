// NEMA-verified: 2026a, checked 2026-10-06 — pins the rules lifted from dicom-video (D269): Modality ES / GM / XC and the PS3.3 2026a A.32.5.4.1 / A.32.6.4.1 / A.32.7.4.1 section numbers; Patient's Sex M / F / O (PS3.3 Table C.7-1); DA form (PS3.6 Table 6-1); PS3.6 Table A-1 registration; the 6 PS3.16 2026a CID 3000 rows and the SCHEME:VALUE[:MEANING] grammar (Code Meaning Type 1, PS3.3 Table 8.8-1)
import XCTest
import DICOMCore
import DICOMKit

/// `VideoOptionConformance` and `AudioChannelSourceOption` in DICOMKit (lifted from the
/// dicom-video CLI, D269). The texts are the CLI's and must not drift (CLI parity).
final class VideoOptionConformanceTests: XCTestCase {

    // MARK: - VideoOptionConformance

    func test_requiredModality_isTheA32ContentConstraint() {
        let expected: [(VideoConsole.TypeArgument, String, String)] = [
            (.endoscopic, "ES", "A.32.5.4.1"),
            (.microscopic, "GM", "A.32.6.4.1"),
            (.photographic, "XC", "A.32.7.4.1"),
        ]
        for (type, modality, section) in expected {
            let required = VideoOptionConformance.requiredModality(for: type)
            XCTAssertEqual(required.value, modality)
            XCTAssertEqual(required.section, section)
            XCTAssertEqual(type.videoType.defaultModality, modality, "engine default for \(type)")
        }
    }

    func test_modalityOtherThanTheIODs_isRefused_withTheCLIText() {
        let lines = VideoOptionConformance.violations(
            type: .photographic, metadata: VideoWorkflow.Metadata(modality: "CT"), transferSyntax: nil)
        XCTAssertEqual(lines, ["--modality CT: PS3.3 A.32.7.4.1 requires Modality (0008,0060) XC for "
                               + "Video Photographic Image Storage; refused."])
        XCTAssertTrue(VideoOptionConformance.violations(
            type: .endoscopic, metadata: VideoWorkflow.Metadata(modality: "ES"), transferSyntax: nil).isEmpty)
        XCTAssertTrue(VideoOptionConformance.violations(
            type: .endoscopic, metadata: VideoWorkflow.Metadata(), transferSyntax: nil).isEmpty)
    }

    func test_patientSex_outsideTableC71_isRefused() {
        XCTAssertEqual(VideoOptionConformance.patientSexValues, ["M", "F", "O"])
        let lines = VideoOptionConformance.violations(
            type: .endoscopic, metadata: VideoWorkflow.Metadata(patientSex: "U"), transferSyntax: nil)
        XCTAssertEqual(lines, ["--patient-sex U is not an Enumerated Value of Patient's Sex (0010,0040) "
                               + "(M, F or O; PS3.3 Table C.7-1); refused."])
        for sex in ["M", "F", "O"] {
            XCTAssertTrue(VideoOptionConformance.violations(
                type: .endoscopic, metadata: VideoWorkflow.Metadata(patientSex: sex), transferSyntax: nil).isEmpty, sex)
        }
    }

    func test_birthDate_notDA_isRefused() {
        let lines = VideoOptionConformance.violations(
            type: .endoscopic, metadata: VideoWorkflow.Metadata(patientBirthDate: "1980-01-02"), transferSyntax: nil)
        XCTAssertEqual(lines, ["--patient-birth-date 1980-01-02 is not a DA value (YYYYMMDD; PS3.5 Table 6.2-1) for "
                               + "Patient's Birth Date (0010,0030); refused."])
        XCTAssertTrue(VideoOptionConformance.violations(
            type: .endoscopic, metadata: VideoWorkflow.Metadata(patientBirthDate: "19800102"), transferSyntax: nil).isEmpty)
    }

    func test_transferSyntax_registeredAccepted_fragmentableHEVCRefused() {
        XCTAssertNil(VideoOptionConformance.transferSyntaxViolation("1.2.840.10008.1.2.4.107"))
        XCTAssertNil(VideoOptionConformance.transferSyntaxViolation("1.2.840.10008.1.2.4.100"))
        let line = VideoOptionConformance.transferSyntaxViolation("1.2.840.10008.1.2.4.107.1")
        XCTAssertEqual(line, "--transfer-syntax 1.2.840.10008.1.2.4.107.1 is not registered in PS3.6 Table A-1; "
                             + "HEVC/H.265 has only the non-fragmentable 1.2.840.10008.1.2.4.107 and .108; refused.")
    }

    func test_violations_areInOptionOrder_andHelpStatesTheRefusal() {
        let metadata = VideoWorkflow.Metadata(patientBirthDate: "bad", patientSex: "U", modality: "CT")
        let lines = VideoOptionConformance.violations(
            type: .microscopic, metadata: metadata, transferSyntax: "1.2.840.10008.1.2.4.108.1")
        XCTAssertEqual(lines.map { $0.prefix(2) }, ["--", "--", "--", "--"])
        XCTAssertTrue(lines[0].hasPrefix("--transfer-syntax"))
        XCTAssertTrue(lines[1].hasPrefix("--modality"))
        XCTAssertTrue(lines[2].hasPrefix("--patient-sex"))
        XCTAssertTrue(lines[3].hasPrefix("--patient-birth-date"))
        XCTAssertTrue(VideoOptionConformance.modalityHelp.hasSuffix("any other value is refused (exit 1)"))
        XCTAssertTrue(VideoOptionConformance.patientSexHelp.hasSuffix("(exit 1, PS3.3 Table C.7-1)"))
        XCTAssertTrue(VideoOptionConformance.patientBirthDateHelp.hasSuffix("(exit 1, VR DA)"))
        XCTAssertTrue(VideoOptionConformance.transferSyntaxHelp.hasSuffix("is refused (exit 1)"))
    }

    // MARK: - AudioChannelSourceOption

    /// PS3.16 2026a CID 3000, dumped from the DocBook by script.
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
        }
        XCTAssertEqual(AudioChannelSourceOption.keywords.map(\.source), VideoAudioChannel.Source.cid3000)
        XCTAssertEqual(AudioChannelSourceOption.optionName, "--audio-channel-source")
        for row in Self.cid3000 { XCTAssertTrue(AudioChannelSourceOption.help.contains(row.keyword), row.keyword) }
        XCTAssertTrue(AudioChannelSourceOption.help.contains("(003A,0208)"))
    }

    func test_parse_keywordAndCodeGrammar() throws {
        XCTAssertEqual(try AudioChannelSourceOption.parse("Doppler-Audio"), .dopplerAudio)
        XCTAssertEqual(try AudioChannelSourceOption.parse("DCM:109111").codeMeaning, "Operator's narrative")
        let local = try AudioChannelSourceOption.parse("99LOCAL:AUD1:Ultrasound microphone")
        XCTAssertEqual(local.codingSchemeDesignator, "99LOCAL")
        XCTAssertEqual(local.codeValue, "AUD1")
        XCTAssertEqual(local.codeMeaning, "Ultrasound microphone")
        XCTAssertThrowsError(try AudioChannelSourceOption.parse("narration")) {
            XCTAssertEqual($0 as? AudioChannelSourceOption.ParseError, .unknown("narration"))
            XCTAssertTrue("\($0)".contains("--audio-channel-source"))
        }
        XCTAssertThrowsError(try AudioChannelSourceOption.parse("99LOCAL:AUD1")) {
            XCTAssertEqual($0 as? AudioChannelSourceOption.ParseError, .missingMeaning("99LOCAL:AUD1"))
        }
    }
}
