// NEMA-verified: 2026a, checked 2026-09-30 — audio notes per PS3.5 2026a 8.2.5/8.2.12 (verified by script): bits per sample of compressed audio stated as not in the bit stream, MP3 complementary channels as not identified, CBR violations of "CBR MPEG-1 LAYER III" (D58)
// NEMA-verified: 2026a, checked 2026-09-30 — SOP Class names match PS3.6 2026a Table A-1; audio messages per PS3.5 2026a 8.2.5-8.2.12 and Table 8.2.12-1 (per-track violations of the constraints VideoConformanceValidator.audioConstraints extracts; audio kept, never stripped) and PS3.3 Table C.7-13 (003A,0300) Type 2C "Zero or more Items", Channel Source from PS3.16 CID 3000 (D34, D46)
// NEMA-verified: 2026a, checked 2026-10-01 — VideoConsole.Help: 16 attribute names diffed by script against PS3.6 2026a Tables 6-1/7-1 (15 matched; "Patient's Name" fixed); modality help per PS3.3 2026a A.32.5.4.1/A.32.6.4.1/A.32.7.4.1 (ES/GM/XC); input help per PS3.5 8.2.7-8.2.11 container rule and the 8.2.5/8.2.6 MPEG-2 containers incl. MPEG-PS / MPEG-PES (D227); help strings only, no public member changed
//
// VideoConsole.swift
// DICOMKit
//
// Copyright © 2026 DICOMKit. All rights reserved.
//

import Foundation
import DICOMCore

/// Console lines, argument parsing and exit codes for `dicom-video` — the single
/// source of truth used by BOTH the CLI and DICOMStudio's CLI Workshop executor,
/// so the two surfaces cannot drift.
///
/// The library must not print, so every function here **returns** text. The CLI
/// writes it to stdout/stderr; the Workshop appends it to the SwiftUI console.
///
/// Reference: `APP_CLI_SHARED_API.md` §6.1 — the `*Console` pattern.
public enum VideoConsole {

    /// Mirrors `CommandConfiguration.version` in the CLI.
    public static let toolVersion = "1.0.0"

    // MARK: - Exit Codes

    /// The exit codes `dicom-video` returns, so scripts (and the Workshop's
    /// status badge) can tell "broken" from "not DICOM-legal".
    public enum ExitCode: Int32, Sendable {
        /// The command did what was asked.
        case success = 0
        /// An I/O or usage error: unreadable input, bad flag combination.
        case inputError = 1
        /// The input was understood but is not DICOM-legal.
        case conformanceRejection = 2
    }

    // MARK: - Stream Prefixes

    /// Prefixes the CLI applies when writing to stderr. Kept here so the app
    /// renders the identical strings rather than inventing its own wording.
    public static func errorLine(_ message: String) -> String { message }
    public static func warningLine(_ message: String) -> String { "warning: " + message }
    public static func noteLine(_ message: String) -> String { "note: " + message }

    // MARK: - Video Type

    /// The `--type` values, and the SOP class each selects.
    ///
    /// `ExpressibleByArgument` is added by the CLI adapter; the library must not
    /// import ArgumentParser, so the raw values are the contract.
    public enum TypeArgument: String, Sendable, CaseIterable {
        case endoscopic
        case microscopic
        case photographic

        /// The library video type this argument selects.
        public var videoType: VideoType {
            switch self {
            case .endoscopic: return .endoscopic
            case .microscopic: return .microscopic
            case .photographic: return .photographic
            }
        }

        /// The SOP class's human-readable name, for the default-type notice.
        public var sopClassName: String {
            switch self {
            case .endoscopic: return "Video Endoscopic Image Storage"
            case .microscopic: return "Video Microscopic Image Storage"
            case .photographic: return "Video Photographic Image Storage"
            }
        }
    }

    /// How a batch run groups its outputs into series.
    public enum SeriesMode: String, Sendable, CaseIterable {
        /// One series for every clip. IHE ENDO 3.10.4.1.1.1 makes this the correct
        /// default: one procedure step on one piece of equipment is one series,
        /// and that holds even when the endoscope is swapped mid-procedure.
        case single
        /// A fresh series per clip, for clips from different procedure steps or
        /// different equipment, where IHE requires separate series.
        case perFile = "per-file"
    }

    /// The note printed when `--type` is left to its default, because a wrong
    /// type yields a valid but mislabelled object.
    public static func defaultTypeNote(_ type: TypeArgument) -> String {
        noteLine("""
            Using SOP class \(type.sopClassName) \
            (modality \(type.videoType.defaultModality)).
                  Override with --type microscopic|photographic.
            """)
    }

    // MARK: - Input Errors

    /// The input file could not be read.
    public static func cannotReadLine(_ path: String) -> String {
        "error: cannot read '\(path)'."
    }

    /// The output file could not be written.
    public static func cannotWriteLine(_ path: String, reason: String) -> String {
        "error: cannot write '\(path)': \(reason)."
    }

    /// The output already exists and `--force` was not given.
    public static func outputExistsLine(_ path: String) -> String {
        "error: '\(path)' already exists. Pass --force to overwrite."
    }

    /// The input to `extract` is not a DICOM file at all.
    public static func notReadableDICOMLine(_ path: String) -> String {
        "error: '\(path)' is not a readable DICOM file."
    }

    /// A `--transfer-syntax` value that is not a registered UID.
    public static func unknownTransferSyntaxLine(_ uid: String) -> String {
        "error: '\(uid)' is not a recognized transfer syntax UID."
    }

    /// A `--transfer-syntax` value that is a real UID but carries still images.
    public static func notAVideoTransferSyntaxLine(_ uid: String) -> String {
        "error: transfer syntax \(uid) is not a video transfer syntax."
    }

    /// `--trust-input` given without the `--transfer-syntax` it requires.
    public static let trustInputNeedsTransferSyntaxLine = """
        error: --trust-input requires an explicit --transfer-syntax, because \
        an unvalidated transport stream declares nothing about itself.
        """

    /// A `--frame-rate` value outside any plausible range.
    public static func implausibleFrameRateLine(_ value: Double) -> String {
        "error: --frame-rate \(formatFrameRateArgument(value)) is not a plausible frame rate."
    }

    /// Renders a `--frame-rate` value the way Swift's own `Double` interpolation
    /// does, so the CLI's message (which interpolates the parsed `Double`) and
    /// the app's agree for every input.
    private static func formatFrameRateArgument(_ value: Double) -> String {
        "\(value)"
    }

    /// No transfer syntax fits and the stream is nonetheless conformant against
    /// the closest candidate — a contradiction worth naming plainly.
    public static let noCarryingTransferSyntaxLine =
        "error: no DICOM video transfer syntax can carry this stream."

    /// The `batch` input path is not a directory.
    public static func notADirectoryLine(_ path: String) -> String {
        "error: '\(path)' is not a directory."
    }

    /// `batch` found nothing worth trying.
    public static func noVideoFilesLine(_ path: String) -> String {
        "error: no video files found in '\(path)'."
    }

    /// `--series-uid` combined with `--series-mode per-file`, which mints its own.
    public static let seriesUIDConflictsWithPerFileLine = """
        error: --series-uid cannot be combined with --series-mode per-file, \
        which generates a new Series Instance UID for every clip.
        """

    /// An unparseable `--series-mode` value.
    public static func invalidSeriesModeLine(_ value: String) -> String {
        invalidValueLines(
            value: value, option: "--series-mode",
            help: "Series grouping: single (default) or per-file"
        ).joined(separator: "\n")
    }

    /// An unparseable `--type` value.
    public static func invalidTypeLine(_ value: String) -> String {
        invalidValueLines(
            value: value, option: "--type",
            help: "Video type: endoscopic, microscopic or photographic"
        ).joined(separator: "\n")
    }

    /// An unparseable `--frame-rate` value.
    public static func invalidFrameRateLine(_ value: String) -> String {
        invalidValueLines(
            value: value, option: "--frame-rate",
            help: "Override the probed frame rate (validated)"
        ).joined(separator: "\n")
    }

    /// An unparseable `--instance-number` / `--series-number` value.
    public static func invalidIntegerLine(_ value: String, option: String, help: String) -> String {
        invalidValueLines(value: value, option: option, help: help).joined(separator: "\n")
    }

    /// The two lines ArgumentParser prints when an option value cannot be parsed:
    /// the error, then the option's help. Reproduced here so the Workshop, whose
    /// form does its own parsing, renders what the CLI would have printed.
    public static func invalidValueLines(value: String, option: String, help: String) -> [String] {
        let valueName = option.hasPrefix("--") ? String(option.dropFirst(2)) : option
        let usage = "\(option) <\(valueName)>"
        return ["Error: The value '\(value)' is invalid for '\(usage)'",
                "Help:  \(usage)  \(help)"]
    }

    // MARK: - Option Help

    /// Help text of the options, single-sourced so the CLI's `@Option(help:)`,
    /// the Workshop's form help, and the invalid-value lines agree.
    public enum Help {
        public static let input = "Input video file: H.264/HEVC in an MP4 or MPEG-2 Transport Stream container (PS3.5 8.2.7-8.2.11); MPEG-2 video in MP4, an MPEG-2 Program Stream, PES or elementary stream (8.2.5, 8.2.6: container not constrained); MOV is probed but not converted"
        public static let output = "Output DICOM file path"
        public static let type = "Video type: endoscopic, microscopic or photographic"
        public static let transferSyntax = "Transfer Syntax UID (auto-detected by default): an MPEG2, MPEG-4 AVC/H.264 or HEVC/H.265 UID of PS3.6 Table A-1"
        public static let frameRate = "Override the probed frame rate (validated)"
        public static let instanceNumber = "Instance Number (default: 1)"
        public static let seriesNumber = "Series Number (default: 1)"
        public static let dryRun = "Probe and validate only; write nothing"
        public static let trustInput = "Encapsulate a transport stream without validating it"
        public static let force = "Overwrite the output file if it exists"
        public static let probeInput = "Input video file"
        public static let probeTrustInput =
            "Treat a transport stream as conformant without validating it"
        public static let extractInput = "Input DICOM file"
        public static let extractOutput = "Output video file path"
        public static let batchInput = "Directory of video files"
        public static let batchOutputDir = "Directory to write DICOM files into"
        public static let seriesMode = "Series grouping: single (default) or per-file"
        public static let recursive = "Descend into subdirectories"
        public static let continueOnError = "Skip failures and convert the rest"
        public static let batchForce = "Overwrite existing output files"
        public static let verbose = "Show the reasoning behind each step"
        public static let patientName = "Patient's Name, in DICOM caret form (e.g. Doe^Jane)"
        public static let patientID = "Patient ID"
        public static let patientBirthDate = "Patient's Birth Date (YYYYMMDD)"
        public static let patientSex = "Patient's Sex (M, F or O)"
        public static let studyUID = "Study Instance UID (generated if not given)"
        public static let seriesUID = "Series Instance UID (generated if not given)"
        public static let accessionNumber = "Accession Number"
        public static let studyID = "Study ID"
        public static let referringPhysician = "Referring Physician's Name"
        public static let seriesDescription = "Series Description"
        public static let modality = "Modality (overrides the video type's default; PS3.3 A.32.5-A.32.7 require ES endoscopic, GM microscopic, XC photographic)"
        public static let manufacturer = "Manufacturer"
        public static let institutionName = "Institution Name"
    }

    // MARK: - Probe Report

    /// Renders a probe result as the report `probe` prints and `convert` echoes.
    ///
    /// The column alignment is part of the contract: both surfaces print the same
    /// 18-column label field.
    public static func describe(
        _ probe: VideoProbeResult,
        transferSyntax: TransferSyntax?
    ) -> String {
        var lines: [String] = []
        lines.append("Container:        \(probe.containerDisplayName)")
        lines.append("Codec:            \(probe.stream.codec.displayName)")
        if probe.stream.codec != .unknown {
            lines.append("Profile:          \(probe.stream.profileName)")
            lines.append("Level:            \(probe.stream.levelDescription)")
            lines.append("Resolution:       \(probe.stream.width)x\(probe.stream.height)")
            lines.append("Chroma:           \(probe.stream.chromaFormat.displayName)")
            lines.append("Bit depth:        \(probe.stream.bitDepthLuma)-bit")
            lines.append("Scan:             \(probe.stream.isProgressive ? "progressive" : "interlaced")")
        }
        if let frameRate = probe.frameRate {
            lines.append("Frame rate:       \(String(format: "%.3f", frameRate)) fps")
        } else {
            lines.append("Frame rate:       not declared")
        }
        lines.append("Frames:           \(probe.frameCount) (\(probe.frameCountSource.rawValue))")
        // Audio is permitted in DICOM video (PS3.5 8.2.5-8.2.12, Table 8.2.12-1)
        // and `convert` keeps it in the bit stream; what DICOMKit cannot yet do
        // is check its format against those constraints.
        if probe.audioTrackCount > 0 {
            if probe.audioTracks.allSatisfy({ $0.format == nil }) {
                lines.append("Audio tracks:     \(probe.audioTrackCount) \(audioTrackNote)")
            } else {
                lines.append("Audio tracks:     \(probe.audioTrackCount) (carried in the bit stream)")
                for (index, track) in probe.audioTracks.enumerated() {
                    let label = "Audio track \(index + 1):"
                    let padded = label.count < 18
                        ? label + String(repeating: " ", count: 18 - label.count)
                        : label + " "
                    lines.append(padded + track.summary)
                }
            }
        }
        if probe.rotationDegrees != 0 {
            lines.append("Rotation:         \(probe.rotationDegrees)° (container display matrix)")
        }
        if let syntax = transferSyntax {
            lines.append("Transfer syntax:  \(syntax.uid)")
            lines.append("                  \(syntax.displayName)")
        }
        return lines.joined(separator: "\n")
    }

    // MARK: - Verbose Reporting

    /// The verbose lines are commentary on decisions the tool already makes
    /// silently: which container was recognised, why a transfer syntax was
    /// chosen, where a frame count came from. They explain a rejection or an
    /// unexpected object without a second run under a debugger, so they are
    /// written for someone asking "why did it pick that?".
    ///
    /// Every one is prefixed `verbose:` and goes to stderr, so `--verbose` never
    /// changes what a script parsing stdout sees.
    public static func verboseLine(_ message: String) -> String {
        "verbose: " + message
    }

    /// Renders a block of verbose lines, or "" when there is nothing to say.
    public static func verboseBlock(_ messages: [String]) -> String {
        messages.map(verboseLine).joined(separator: "\n")
    }

    /// The verbose preamble for a single conversion: what was read, and how the
    /// bytes are being interpreted before any decision is made.
    public static func verboseReadLines(
        byteCount: Int,
        container: VideoContainer
    ) -> [String] {
        ["read \(byteCount) bytes; container detected as \(container.displayName)"]
    }

    /// Which transfer syntax the run settled on, and where it came from.
    public static func verboseSelectedSyntaxLine(
        _ syntax: TransferSyntax,
        wasExplicit: Bool = false
    ) -> String {
        let source = wasExplicit
            ? "named by --transfer-syntax"
            : "selected from the bitstream's codec, profile and level"
        return "transfer syntax \(syntax.uid) \(source)"
    }

    /// The verbose counterpart to a "nothing carries this" verdict, naming the
    /// syntax whose constraints the report below is measured against.
    public static func verboseNoCandidateSyntaxLine(_ candidate: TransferSyntax) -> String {
        "no transfer syntax carries this stream; "
            + "reporting against the closest candidate, \(candidate.displayName)"
    }

    /// Why the run ended up on this transfer syntax — the decision `convert` and
    /// `batch` otherwise make without saying anything.
    ///
    /// The conformance line is stated only where the run has actually validated
    /// the stream; `probe`, which prints its own verdict, uses
    /// ``verboseSelectedSyntaxLine(_:wasExplicit:)`` alone.
    public static func verboseTransferSyntaxLines(
        _ syntax: TransferSyntax,
        wasExplicit: Bool,
        trusted: Bool
    ) -> [String] {
        if trusted {
            return ["transfer syntax \(syntax.uid) taken on trust (--trust-input); "
                    + "the stream was not validated"]
        }
        return [verboseSelectedSyntaxLine(syntax, wasExplicit: wasExplicit),
                "validated the stream against \(syntax.displayName): conformant"]
    }

    /// Where the frame count came from, which decides Number of Frames and is
    /// the usual reason a converted clip reports an unexpected duration.
    public static func verboseFrameCountLine(
        _ count: Int,
        source: VideoProbeResult.FrameCountSource
    ) -> String {
        "frame count \(count) from \(source.rawValue)"
    }

    /// The frame-rate override, which silently replaces what the bitstream said.
    public static func verboseFrameRateOverrideLine(
        from probed: Double?,
        to override: Double
    ) -> String {
        let previous = probed.map { String(format: "%.3f", $0) + " fps" } ?? "not declared"
        return "frame rate overridden: \(previous) -> "
            + String(format: "%.3f", override) + " fps"
    }

    /// The UIDs the object was built with, so an operator can find it again
    /// without re-reading the file they just wrote.
    public static func verboseIdentityLines(
        sopClassName: String,
        studyUID: String,
        seriesUID: String,
        sopInstanceUID: String,
        generatedStudyUID: Bool,
        generatedSeriesUID: Bool
    ) -> [String] {
        func note(_ generated: Bool) -> String { generated ? " (generated)" : " (given)" }
        return [
            "SOP class \(sopClassName)",
            "Study Instance UID  \(studyUID)\(note(generatedStudyUID))",
            "Series Instance UID \(seriesUID)\(note(generatedSeriesUID))",
            "SOP Instance UID    \(sopInstanceUID) (generated)",
        ]
    }

    /// The encoded size, next to the payload it carries, which is what shows
    /// that remuxing did not re-encode the pixels.
    public static func verboseEncodedLines(
        payloadBytes: Int,
        encodedBytes: Int
    ) -> [String] {
        let overhead = encodedBytes - payloadBytes
        return ["encoded \(encodedBytes) bytes: \(payloadBytes) bytes of bitstream "
                + "carried unchanged, \(overhead) bytes of DICOM overhead"]
    }

    /// What `extract` found inside the object before it wrote anything.
    public static func verboseExtractLines(_ extracted: ExtractedVideo) -> [String] {
        var lines = ["payload recovered from \(extracted.fragmentCount) "
                     + "fragment\(extracted.fragmentCount == 1 ? "" : "s")"]
        lines.append("container detected from the payload's own bytes as "
                     + extracted.container.displayName)
        return lines
    }

    /// What a batch run is about to do, before the per-clip lines start.
    public static func verboseBatchPlanLines(
        fileCount: Int,
        recursive: Bool,
        seriesMode: SeriesMode
    ) -> [String] {
        let grouping = seriesMode == .single
            ? "one series for all of them"
            : "a new series per clip"
        return ["found \(fileCount) candidate file\(fileCount == 1 ? "" : "s")"
                + (recursive ? " (searched subdirectories)" : ""),
                "series mode \(seriesMode.rawValue): \(grouping)",
                "clips are converted in natural-sort order"]
    }

    /// The per-clip verbose line inside a batch run, naming the numbering the
    /// clip received — which is what a reader checks when a series looks wrong.
    public static func verboseBatchItemLine(
        name: String,
        seriesNumber: Int,
        instanceNumber: Int,
        transferSyntaxUID: String
    ) -> String {
        "\(name): series \(seriesNumber), instance \(instanceNumber), \(transferSyntaxUID)"
    }

    /// The qualifier after the probe report's audio track count.
    ///
    /// DICOM video may carry audio: PS3.5 8.2.5 (MPEG2, applied to MP@HL by
    /// 8.2.6) says "Any audio components present within the MPEG bit stream shall
    /// comply with the following restrictions" (CBR MP3), and 8.2.7-8.2.11 (H.264,
    /// HEVC) say "Any audio components included in the data container shall follow
    /// the constraints detailed in" 8.2.12, whose Table 8.2.12-1 allows AAC, MP3
    /// and MPEG-1 Audio Layer II in MP4 (plus LPCM and AC-3 in MPEG-2 TS).
    public static let audioTrackNote =
        "(carried in the bit stream; not checked against PS3.5 8.2.5/8.2.12)"

    /// The warning emitted when the input has audio tracks whose format could not
    /// be identified (``audioCheckLines(_:channelsDescribed:sourceGiven:)`` is
    /// used once any format is known).
    ///
    /// The audio is not removed: `convert` encapsulates the payload unchanged,
    /// which PS3.5 8.2.5-8.2.12 permit. The warning names the library's
    /// limitations instead — it does not check the audio against the codec, sample
    /// rate and channel constraints of PS3.5 8.2.5 / 8.2.12 (Table 8.2.12-1), and
    /// it writes Multiplexed Audio Channels Description Code Sequence (003A,0300)
    /// with no Items (Type 2C, "Zero or more Items", PS3.3 Table C.7-13) because it
    /// does not read the channel layout.
    public static func audioCarriedLine(trackCount: Int) -> String {
        warningLine("""
            input has \(trackCount) audio track\(trackCount == 1 ? "" : "s"), \
            kept in the bit stream; DICOMKit does not check \(trackCount == 1 ? "it" : "them") \
            against PS3.5 8.2.5/8.2.12 or describe \(trackCount == 1 ? "its" : "their") channels \
            in (003A,0300).
            """)
    }

    /// The note emitted when audio is carried into the object.
    ///
    /// The payload is encapsulated unchanged, so its audio travels with it.
    /// PS3.5 8.2.5 and 8.2.12 permit that, and the tracks have already passed
    /// their rules by the time this is printed.
    public static func audioCarriedLine(_ tracks: [AudioStreamInfo]) -> String {
        let count = tracks.count
        let summaries = tracks.map(\.summary).joined(separator: "; ")
        return noteLine("""
            carrying \(count) audio track\(count == 1 ? "" : "s") (\(summaries)) \
            inside the encapsulated bit stream, as PS3.5 8.2.5 and 8.2.12 permit.
            """)
    }

    /// The warning emitted when the container asks players to rotate the video.
    ///
    /// DICOM has no attribute for display rotation, so viewers show the coded
    /// picture as stored. A warning rather than a rejection: the pixel data is
    /// intact, and baking the rotation in means re-encoding, which is the
    /// user's decision.
    public static func rotationWarningLine(_ degrees: Int) -> String {
        warningLine("""
            the container asks players to rotate this video by \(degrees)°, which DICOM \
            cannot record; DICOM viewers will show it unrotated. To bake the rotation in, \
            re-encode it (ffmpeg applies the rotation automatically when re-encoding).
            """)
    }

    /// The notices for the audio tracks of a conversion, after checking them
    /// against PS3.5 8.2.5 (MPEG2) or 8.2.12 (H.264, HEVC) for its transfer
    /// syntax.
    ///
    /// When no track's format could be identified this is exactly
    /// ``audioCarriedLine(trackCount:)``. Otherwise, per track: one warning per
    /// known violation; a note listing the constraints that could not be checked;
    /// or a note that the track meets the section; then one note per
    /// ``VideoAudioTrackCheck/notes`` entry (bits per sample of compressed audio,
    /// which no bit stream carries; MP3 complementary channels, not identified). Then, unless channels were
    /// described, a note that (003A,0300) has no Items. The audio is never
    /// removed or re-encoded, whatever the verdict.
    ///
    /// - Parameters:
    ///   - result: ``VideoConformanceValidator/validateAudio(tracks:container:transferSyntax:)``.
    ///   - channelsDescribed: Whether (003A,0300) carries Items.
    ///   - sourceGiven: Whether the caller named a Channel Source, so a missing
    ///     description is down to the channel layout rather than the source.
    public static func audioCheckLines(
        _ result: VideoAudioConformanceResult,
        channelsDescribed: Bool = false,
        sourceGiven: Bool = false
    ) -> [String] {
        guard !result.tracks.isEmpty else { return [] }
        if result.tracks.allSatisfy({ $0.track.format == nil }) {
            return [audioCarriedLine(trackCount: result.tracks.count)]
        }
        var lines: [String] = []
        for check in result.tracks {
            let label = "audio track \(check.trackNumber) (\(check.track.summary))"
            guard check.track.format != nil else {
                lines.append(warningLine(
                    "\(label): format not identified; not checked against \(result.section)."))
                continue
            }
            for violation in check.violations {
                lines.append(audioViolationLine(label: label, violation: violation))
            }
            if !check.notChecked.isEmpty {
                let list = check.notChecked.map(\.rawValue).joined(separator: ", ")
                lines.append(noteLine("\(label): not checked against \(result.section): \(list)."))
            } else if check.violations.isEmpty {
                let qualifier = check.notes.isEmpty ? "" : " as far as the bit stream shows"
                lines.append(noteLine("\(label) meets \(result.section)\(qualifier)."))
            }
            // Why a constraint cannot be read, or stays not checked (D58).
            for note in check.notes {
                lines.append(noteLine("\(label): \(note.message)."))
            }
        }
        if !channelsDescribed {
            lines.append(sourceGiven ? audioChannelLayoutUndescribedLine : audioChannelsUndescribedLine)
        }
        return lines
    }

    /// One audio violation as a warning: the audio is kept, so it is not an error.
    public static func audioViolationLine(label: String, violation: VideoAudioViolation) -> String {
        warningLine("\(label): \(violation.message); the audio is kept unchanged.")
    }

    /// Why (003A,0300) has no Items even though the audio was identified.
    public static let audioChannelsUndescribedLine = noteLine("""
        Multiplexed Audio Channels Description Code Sequence (003A,0300) has no Items: \
        each Item needs a Channel Source code (PS3.16 CID 3000) that the container does not record.
        """)

    /// Why (003A,0300) has no Items although a Channel Source was given: some
    /// track is not one mono or stereo signal, which is all Channel Mode
    /// (003A,0302) can express (Enumerated Values MONO, STEREO), or its channel
    /// count is unknown.
    /// The refusal when per-track Channel Sources do not fit the audio tracks
    /// (``VideoWorkflow/validateAudioChannelSources(for:metadata:)``).
    public static func audioChannelSourceCountLine(given: Int, tracks: Int) -> String {
        errorLine("""
            --audio-channel-source given \(given) times, but the input has \(tracks) audio \
            track\(tracks == 1 ? "" : "s"): give it once (for every track) or once per track, in order \
            (PS3.3 Table C.7-13: one Multiplexed Audio Channels Description Code Sequence (003A,0300) \
            Item per channel, each with its own Channel Source Sequence (003A,0208)).
            """)
    }

    public static let audioChannelLayoutUndescribedLine = noteLine("""
        Multiplexed Audio Channels Description Code Sequence (003A,0300) has no Items: \
        Channel Mode (003A,0302) is MONO or STEREO, and not every audio track is known to be one of those.
        """)

    /// The warning formerly emitted when audio tracks were said to be dropped.
    ///
    /// Its text claimed "DICOM video has no audio, discarding", which is wrong
    /// twice: PS3.5 8.2.5-8.2.12 permit audio, and `convert` never removed it.
    /// It now returns ``audioCarriedLine(trackCount:)``.
    @available(*, deprecated, renamed: "audioCarriedLine(trackCount:)", message: "Audio is permitted in DICOM video (PS3.5 2026a 8.2.5-8.2.12, Table 8.2.12-1) and is kept in the bit stream; use audioCarriedLine(trackCount:)")
    public static func audioDiscardedLine(trackCount: Int) -> String {
        audioCarriedLine(trackCount: trackCount)
    }

    /// The `probe` conformance verdict lines.
    public static let conformanceOKLine = "\nConformance:      OK"
    public static let noCarryingSyntaxVerdictLine =
        "\nConformance:      no DICOM video transfer syntax carries this stream"

    // MARK: - Convert Results

    /// The line naming the object that was written.
    public static func wroteLine(_ path: String) -> String { "Wrote \(path)" }

    /// The trailer of a `--dry-run`, after the probe report.
    public static let dryRunTrailer = "\nDry run: conformant, nothing written."

    // MARK: - Extract Results

    /// The line naming the bitstream that was written, with its size.
    public static func extractedLine(path: String, byteCount: Int) -> String {
        "Wrote \(path) (\(byteCount) bytes)"
    }

    /// The payload summary `extract` prints after writing.
    public static func extractSummary(_ extracted: ExtractedVideo) -> String {
        """
        Codec:            \(extracted.codec.displayName)
        Container:        \(extracted.containerDisplayName)
        Transfer syntax:  \(extracted.transferSyntax.uid)
        """
    }

    /// The warning for an output extension that does not suit the payload. A
    /// mismatched extension is a warning, not an error: the user may have a
    /// reason, but a `.mp4` holding an elementary stream will not play.
    public static func extensionMismatchLine(
        container: VideoContainer,
        suggested: String,
        given: String
    ) -> String {
        warningLine("""
            payload is \(container.displayName); \
            '.\(suggested)' would suit it better than '.\(given)'.
            """)
    }

    /// The warning for a payload that contradicts the transfer syntax the object
    /// declares.
    ///
    /// A warning rather than an error: extracting from a non-conformant object is
    /// a legitimate thing to want to do, often precisely because it is being
    /// diagnosed. Refusing would make the tool useless for recovery, while saying
    /// nothing attributes the defect to whatever reads the payload next.
    public static func payloadContradictsTransferSyntaxLine(
        transferSyntax: TransferSyntax,
        violation: VideoConformanceViolation
    ) -> String {
        warningLine("""
            the object declares \(transferSyntax.uid) (\(transferSyntax.displayName)) \
            but \(violation.message); the source object is non-conformant. \
            The bit stream was extracted unchanged.
            """)
    }

    // MARK: - Batch Results

    /// The per-clip success line.
    public static func batchConvertedLine(input: String, output: String) -> String {
        "\(input) -> \(output)"
    }

    /// The per-clip line of a batch `--dry-run`.
    public static func batchDryRunLine(input: String, transferSyntaxUID: String) -> String {
        "\(input): OK (\(transferSyntaxUID))"
    }

    /// The `--force`-less collision inside a batch run.
    public static func batchOutputExistsLine(_ name: String) -> String {
        "'\(name)' already exists; pass --force"
    }

    /// The unreadable-clip reason inside a batch run.
    public static let batchUnreadableLine = "cannot read the file"

    /// The batch summary block, including any skipped clips.
    public static func batchSummary(
        converted: Int,
        total: Int,
        skipped: [(name: String, reason: String)]
    ) -> String {
        var lines: [String] = [""]
        if skipped.isEmpty {
            lines.append("Converted \(converted) of \(total) clips.")
        } else {
            lines.append("Converted \(converted) of \(total) clips (\(skipped.count) skipped).")
            for entry in skipped {
                lines.append("  skipped: \(entry.name) — \(entry.reason)")
            }
        }
        return lines.joined(separator: "\n")
    }

    /// The fail-fast trailer, naming where the run stopped.
    public static func batchStoppedLines(at name: String, converted: Int) -> String {
        "\nStopped at '\(name)'. \(converted) file(s) already written."
    }

    /// Reduces a multi-line failure to the one line the skip list shows.
    public static func firstLine(of message: String) -> String {
        let trimmed = message
            .split(separator: "\n", omittingEmptySubsequences: false)
            .first.map(String.init) ?? message
        return trimmed.replacingOccurrences(of: "error: ", with: "")
    }

    // MARK: - Conformance Reporting

    /// Renders a violation the way a rejection prints it: the message, then the
    /// indented remedy when one exists.
    public static func violationReport(_ violation: VideoConformanceViolation) -> String {
        var text = "error: \(violation.message)"
        if let remedy = violation.remedy {
            text += "\n\n       \(remedy)"
        }
        return text
    }
}
