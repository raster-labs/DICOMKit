// NEMA-verified: 2026a, checked 2026-10-06 — lifted from Sources/dicom-video/AudioChannelSourceOption.swift (D269) so dicom-video and the DICOMStudio CLI Workshop share one copy; the 6 keywords re-checked by script against the 6 rows of PS3.16 2026a CID 3000 (Audio Channel Source, Type: Extensible): DCM 109110 Voice, 109111 Operator's narrative, 109112 Ambient room environment, 109113 Doppler audio, 109114 Phonocardiogram, 109115 Physiological audio signal, exact Code Value / Coding Scheme Designator / Code Meaning; one value per audio track (repeatable, P-AUDIO-SOURCE-PER-TRACK) or one for all; each is written as the single Item of Channel Source Sequence (003A,0208), Type 1, in each Multiplexed Audio Channels Description Code Sequence (003A,0300) Item (PS3.3 2026a Table C.7-13, Cine Module); Code Meaning is Type 1 in the Code Sequence Macro (PS3.3 Table 8.8-1), so a bare SCHEME:VALUE is accepted only for a listed code
//
// AudioChannelSourceOption.swift
// DICOMKit
//
// Copyright © 2026 DICOMKit. All rights reserved.
//

import Foundation
import DICOMCore

/// The `--audio-channel-source` values of `convert` and `batch` (D56), shared by
/// `dicom-video` and the DICOMStudio CLI Workshop (D269).
///
/// No container records what the multiplexed audio is, so the caller names it.
/// The engine then writes one (003A,0300) Item per audio track with the code as
/// its Channel Source Sequence (003A,0208): one value is the source of every
/// track (`VideoWorkflow.Metadata.audioChannelSource`); repeated values are one
/// per track in container order (`audioChannelSources`, P-AUDIO-SOURCE-PER-TRACK).
/// Without it the sequence stays empty, as before.
public enum AudioChannelSourceOption {
    public static let optionName = "--audio-channel-source"

    /// PS3.16 2026a CID 3000 Audio Channel Source, all 6 rows in table
    /// order; the keyword is the Code Meaning in lower-case hyphenated form.
    public static let keywords: [(keyword: String, source: VideoAudioChannel.Source)] = [
        ("voice", VideoAudioChannel.Source(dcmCodeValue: "109110", codeMeaning: "Voice")),
        ("operators-narrative", VideoAudioChannel.Source(dcmCodeValue: "109111", codeMeaning: "Operator's narrative")),
        ("ambient-room-environment", VideoAudioChannel.Source(dcmCodeValue: "109112", codeMeaning: "Ambient room environment")),
        ("doppler-audio", VideoAudioChannel.Source(dcmCodeValue: "109113", codeMeaning: "Doppler audio")),
        ("phonocardiogram", VideoAudioChannel.Source(dcmCodeValue: "109114", codeMeaning: "Phonocardiogram")),
        ("physiological-audio-signal", VideoAudioChannel.Source(dcmCodeValue: "109115", codeMeaning: "Physiological audio signal")),
    ]

    public static var keywordList: String { keywords.map(\.keyword).joined(separator: ", ") }

    public static var help: String {
        """
        Source of the multiplexed audio (PS3.16 CID 3000): a keyword or SCHEME:VALUE[:MEANING] \
        (the CID is Extensible; MEANING is required for a code that is not listed). Given once, it \
        applies to every audio track; repeated, it gives one source per audio track in container \
        order, and a count that does not match the tracks exits 1. It is written as the Channel \
        Source Sequence (003A,0208) of each Multiplexed Audio Channels Description Code Sequence \
        (003A,0300) Item (PS3.3 Table C.7-13: one Item per channel, each with its own source); \
        without it that sequence has no Items. Keywords: \(keywordList)
        """
    }

    public enum ParseError: Error, CustomStringConvertible, Equatable {
        case unknown(String)
        case missingMeaning(String)

        public var description: String {
            switch self {
            case .unknown(let value):
                return "\(optionName): \"\(value)\" is neither a listed keyword nor SCHEME:VALUE[:MEANING]; keywords: \(keywordList)"
            case .missingMeaning(let value):
                return "\(optionName): \"\(value)\" is not a listed code, so its Code Meaning is required (SCHEME:VALUE:MEANING)"
            }
        }
    }

    /// A keyword (case-insensitive), `SCHEME:VALUE` for a listed code, or
    /// `SCHEME:VALUE:MEANING` for any code.
    public static func parse(_ value: String) throws -> VideoAudioChannel.Source {
        let trimmed = value.trimmingCharacters(in: .whitespaces)
        if let match = keywords.first(where: { $0.keyword == trimmed.lowercased() }) {
            return match.source
        }
        let parts = trimmed.split(separator: ":", maxSplits: 2, omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
        guard parts.count >= 2, !parts[0].isEmpty, !parts[1].isEmpty else {
            throw ParseError.unknown(value)
        }
        let scheme = parts[0], code = parts[1]
        if parts.count == 3, !parts[2].isEmpty {
            return VideoAudioChannel.Source(CodedConcept(
                codeValue: code, codingSchemeDesignator: scheme, codeMeaning: parts[2]))
        }
        guard let listed = keywords.first(where: {
            $0.source.codeValue == code && $0.source.codingSchemeDesignator == scheme
        }) else {
            throw ParseError.missingMeaning(value)
        }
        return listed.source
    }
}
