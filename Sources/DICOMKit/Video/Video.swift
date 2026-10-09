// NEMA-verified: 2026a, checked 2026-09-30 — Channel Source (003A,0208) keeps any code: PS3.3 2026a Table C.7-13 includes Table 8.8-1 with "DCID 3000" and PS3.16 2026a CID 3000 Audio Channel Source is "Type: Extensible" (DCM 109110-109115 verified by script) (D57)
// NEMA-verified: 2026a, checked 2026-09-30 — video transfer syntax UIDs match PS3.6 2026a Table A-1; Lossy Image Compression Method terms ISO_13818_2/ISO_14496_10/ISO_23008_2 per PS3.3 C.7.6.1.1.5.1; Cine Module fields and audio statements per PS3.3 Table C.7-13 ((003A,0300) Type 2C, "Zero or more Items"; items (003A,0301) IS 1, (003A,0302) CS 1 MONO/STEREO, (003A,0208) SQ 1 one Item, DCID 3000; VRs per PS3.6 Table 6-1), C.7.6.5.1.2-3 and PS3.5 8.2.5/8.2.12; CID 3000 codes per PS3.16 (P-VIDEO, D34, D46)
//
// Video.swift
// DICOMKit
//
// Created by DICOMKit on 2026-02-09.
// Copyright © 2026 DICOMKit. All rights reserved.
//

import Foundation
import DICOMCore

/// Represents a DICOM Video IOD
///
/// Video objects store multi-frame image sequences captured from endoscopic, microscopic,
/// or photographic equipment. Each video contains encapsulated pixel data compressed
/// using MPEG2, H.264/AVC, or H.265/HEVC video codecs.
///
/// ## Audio
///
/// DICOM video **may** carry audio inside the encapsulated bit stream. PS3.5 8.2.5
/// (MPEG2 MP@ML, applied to MP@HL by 8.2.6): "Any audio components present within
/// the MPEG bit stream shall comply with the following restrictions: CBR MPEG-1
/// LAYER III (MP3) Audio Standard, up to 24 bits, 32 kHz, 44.1 kHz or 48 kHz for
/// the main channel …, one main mono or stereo channel, and optionally one or more
/// complementary channel(s)". PS3.5 8.2.7–8.2.11 (H.264, HEVC): "Any audio
/// components included in the data container shall follow the constraints detailed
/// in 8.2.12", whose Table 8.2.12-1 allows LPCM, AC-3, AAC, MP3 and MPEG-1 Layer II
/// in an MPEG-2 TS container and AAC, MP3 and MPEG-1 Layer II in an MP4 container.
/// The Cine Module then describes the channels in Multiplexed Audio Channels
/// Description Code Sequence (003A,0300) (PS3.3 Table C.7-13, C.7.6.5.1.3), see
/// ``multiplexedAudioChannels``.
///
/// Supported SOP Classes:
/// - Video Endoscopic Image Storage (1.2.840.10008.5.1.4.1.1.77.1.1.1)
/// - Video Microscopic Image Storage (1.2.840.10008.5.1.4.1.1.77.1.2.1)
/// - Video Photographic Image Storage (1.2.840.10008.5.1.4.1.1.77.1.4.1)
///
/// Reference: PS3.3 A.32.5 - Video Endoscopic Image IOD
/// Reference: PS3.3 A.32.6 - Video Microscopic Image IOD
/// Reference: PS3.3 A.32.7 - Video Photographic Image IOD
public struct Video: Sendable {

    // MARK: - SOP Class UIDs

    /// Video Endoscopic Image Storage SOP Class UID
    public static let videoEndoscopicImageStorageUID = "1.2.840.10008.5.1.4.1.1.77.1.1.1"

    /// Video Microscopic Image Storage SOP Class UID
    public static let videoMicroscopicImageStorageUID = "1.2.840.10008.5.1.4.1.1.77.1.2.1"

    /// Video Photographic Image Storage SOP Class UID
    public static let videoPhotographicImageStorageUID = "1.2.840.10008.5.1.4.1.1.77.1.4.1"

    // MARK: - Standard-Mandated Defaults

    /// Photometric Interpretation required of every DICOM video transfer syntax.
    ///
    /// PS3.5 Sections 8.2.7, 8.2.10 and 8.2.11 each state "Photometric Interpretation
    /// (0028,0004) shall be YBR_PARTIAL_420". Note that `YBR_PARTIAL_422` is retired
    /// (PS3.3 C.7.6.3) and `YBR_FULL_422` describes a different subsampling entirely.
    public static let defaultPhotometricInterpretation = "YBR_PARTIAL_420"

    /// Default Image Type (0008,0008) for camera-captured video.
    ///
    /// `ImageType` is Type 1 in the VL Image Module (PS3.3 C.8.12).
    public static let defaultImageType = ["ORIGINAL", "PRIMARY"]

    // MARK: - Identification

    /// SOP Instance UID
    public let sopInstanceUID: String

    /// SOP Class UID
    public let sopClassUID: String

    /// Study Instance UID
    public let studyInstanceUID: String

    /// Series Instance UID
    public let seriesInstanceUID: String

    /// Instance Number
    public let instanceNumber: Int?

    // MARK: - Patient Information

    /// Patient Name
    public let patientName: String?

    /// Patient ID
    public let patientID: String?

    // MARK: - Series Information

    /// Modality (typically "ES" for endoscopy, "GM" for microscopy, "XC" for photography)
    public let modality: String?

    /// Series Description
    public let seriesDescription: String?

    /// Series Number
    public let seriesNumber: Int?

    // MARK: - Image Information

    /// Number of rows (height) in pixels
    public let rows: Int

    /// Number of columns (width) in pixels
    public let columns: Int

    /// Number of frames in the video
    public let numberOfFrames: Int

    /// Samples per pixel (typically 3 for RGB/YBR)
    public let samplesPerPixel: Int

    /// Photometric Interpretation (e.g., "YBR_FULL_422", "YBR_PARTIAL_420", "RGB")
    public let photometricInterpretation: String

    /// Bits allocated per sample
    public let bitsAllocated: Int

    /// Bits stored per sample
    public let bitsStored: Int

    /// High bit position
    public let highBit: Int

    /// Pixel representation (0 = unsigned, 1 = signed)
    public let pixelRepresentation: Int

    /// Planar configuration (0 = interleaved, 1 = separate planes)
    public let planarConfiguration: Int?

    // MARK: - Cine Module

    /// Frame time in milliseconds between frames
    public let frameTime: Double?

    /// Cine Rate (frames/second at acquisition)
    public let cineRate: Int?

    /// Recommended Display Frame Rate (frames/second for display)
    public let recommendedDisplayFrameRate: Int?

    /// Frame Delay in milliseconds
    public let frameDelay: Double?

    /// Actual Frame Duration in milliseconds
    public let actualFrameDuration: Int?

    /// Start Trim frame number
    public let startTrim: Int?

    /// Stop Trim frame number
    public let stopTrim: Int?

    /// Frame Time Vector (0018,1065), Type 1C — "the real time increments (in msec)
    /// between Frames"; "The first Frame always has a time increment of 0"
    /// (PS3.3 C.7.6.5.1.2). When set, Frame Increment Pointer (0028,0009) points at
    /// it instead of Frame Time.
    public let frameTimeVector: [Double]?

    /// Preferred Playback Sequencing (0018,1244), Type 3. Enumerated Values
    /// (PS3.3 Table C.7-13): 0 = Looping (1,2…n,1,2,…n,…), 1 = Sweeping (1,2,…n,n-1,…2,1,…).
    public let preferredPlaybackSequencing: Int?

    /// Image Trigger Delay (0018,1067), Type 3 — "Delay time in milliseconds from
    /// trigger (e.g., X-Ray on pulse) to the first Frame".
    public let imageTriggerDelay: Double?

    /// Effective Duration (0018,0072), Type 3 — "Total time in seconds that data was
    /// actually taken for the entire Multi-frame Image".
    public let effectiveDuration: Double?

    /// Multiplexed Audio Channels Description Code Sequence (003A,0300), Type 2C —
    /// "Required if the Transfer Syntax used to encode the Multi-frame Image contains
    /// multiplexed (interleaved) audio channels" (PS3.3 Table C.7-13). Empty when
    /// the bit stream carries no audio, or when it carries audio whose channels
    /// have not been described (see ``VideoWorkflow``).
    public let multiplexedAudioChannels: [VideoAudioChannel]

    /// True when the encapsulated bit stream is known to carry audio even though
    /// ``multiplexedAudioChannels`` describes none of it.
    ///
    /// Multiplexed Audio Channels Description Code Sequence (003A,0300) is Type 2C
    /// and takes "Zero or more Items" (PS3.3 Table C.7-13), so once the condition
    /// "the Transfer Syntax … contains multiplexed (interleaved) audio channels"
    /// holds, the sequence is written even with no Items. ``VideoWorkflow`` sets
    /// this when an MP4 input has a `soun` track: the bit stream is encapsulated
    /// unchanged, audio included, but DICOMKit does not yet identify the channel
    /// numbering, mode or source that an Item would need. ``VideoParser`` sets it
    /// when a parsed object carries the sequence, so the sequence survives a
    /// round trip even when it has no Items.
    var containsUndescribedMultiplexedAudio = false

    /// Whether the object declares multiplexed audio: Multiplexed Audio Channels
    /// Description Code Sequence (003A,0300) is present, with or without Items.
    ///
    /// PS3.3 C.7.6.5.1.3 Note: "If no audio was recorded, the Multiplexed Audio
    /// Channels Description Code Sequence (003A,0300) will be present and contain
    /// no Items", so presence alone does not prove there is audio.
    public var declaresMultiplexedAudio: Bool {
        containsUndescribedMultiplexedAudio || !multiplexedAudioChannels.isEmpty
    }

    // MARK: - Content Date/Time

    /// Content Date
    public let contentDate: DICOMDate?

    /// Content Time
    public let contentTime: DICOMTime?

    // MARK: - Compression Information

    /// Lossy Image Compression ("00" = no, "01" = yes)
    public let lossyImageCompression: String?

    /// Lossy Image Compression Ratio
    public let lossyImageCompressionRatio: Double?

    /// Lossy Image Compression Method (e.g., "ISO_14496_10" for H.264)
    public let lossyImageCompressionMethod: String?

    // MARK: - VL Image Module (PS3.3 C.8.12)

    /// Image Type (0008,0008) — Type 1 in the VL Image Module.
    ///
    /// Defaults to `ORIGINAL\PRIMARY` for camera-captured video.
    public let imageType: [String]

    // MARK: - General Equipment Module (PS3.3 C.7.5.1)

    /// Manufacturer (0008,0070) — Type 2; emitted zero-length when nil.
    public let manufacturer: String?

    /// Manufacturer's Model Name (0008,1090) — Type 3.
    public let manufacturerModelName: String?

    /// Device Serial Number (0018,1000) — Type 3.
    public let deviceSerialNumber: String?

    /// Software Versions (0018,1020) — Type 3.
    public let softwareVersions: String?

    /// Institution Name (0008,0080) — Type 3.
    public let institutionName: String?

    // MARK: - General Acquisition Module (PS3.3 C.7.10.1)

    /// Acquisition Date (0008,0022) — Type 3.
    public let acquisitionDate: DICOMDate?

    /// Acquisition Time (0008,0032) — Type 3.
    public let acquisitionTime: DICOMTime?

    // MARK: - General Image Module (PS3.3 C.7.6.1)

    /// Patient Orientation (0020,0020) — Type 2C; emitted zero-length when nil.
    public let patientOrientation: String?

    // MARK: - General Study Module (PS3.3 C.7.2.1)

    /// Study Date (0008,0020) — Type 2; emitted zero-length when nil.
    public let studyDate: DICOMDate?

    /// Study Time (0008,0030) — Type 2; emitted zero-length when nil.
    public let studyTime: DICOMTime?

    /// Referring Physician's Name (0008,0090) — Type 2; emitted zero-length when nil.
    public let referringPhysicianName: String?

    /// Study ID (0020,0010) — Type 2; emitted zero-length when nil.
    public let studyID: String?

    /// Accession Number (0008,0050) — Type 2; emitted zero-length when nil.
    public let accessionNumber: String?

    // MARK: - Patient Module (PS3.3 C.7.1.1)

    /// Patient's Birth Date (0010,0030) — Type 2; emitted zero-length when nil.
    public let patientBirthDate: DICOMDate?

    /// Patient's Sex (0010,0040) — Type 2; emitted zero-length when nil.
    public let patientSex: String?

    // MARK: - Pixel Data

    /// The encapsulated video pixel data
    public let pixelData: Data?

    /// Stereo Pairs Present (0022,0028): true writes YES, nil omits it.
    ///
    /// Required YES for the H.264 "For 3D Video" (.105) and Stereo High (.106)
    /// transfer syntaxes (PS3.5 Table 8-8, Section 8.2.9).
    public let stereoPairsPresent: Bool?

    /// Whether the transfer syntax lets Pixel Data span several fragments.
    ///
    /// Only then is a payload too large for one 32-bit Item split; otherwise the
    /// whole bit stream goes in one fragment, as PS3.5 requires.
    public let allowsMultipleFragments: Bool

    // MARK: - Initialization

    /// Creates a Video instance
    public init(
        sopInstanceUID: String,
        sopClassUID: String,
        studyInstanceUID: String,
        seriesInstanceUID: String,
        instanceNumber: Int? = nil,
        patientName: String? = nil,
        patientID: String? = nil,
        modality: String? = nil,
        seriesDescription: String? = nil,
        seriesNumber: Int? = nil,
        rows: Int,
        columns: Int,
        numberOfFrames: Int,
        samplesPerPixel: Int = 3,
        photometricInterpretation: String = Video.defaultPhotometricInterpretation,
        bitsAllocated: Int = 8,
        bitsStored: Int = 8,
        highBit: Int = 7,
        pixelRepresentation: Int = 0,
        planarConfiguration: Int? = nil,
        frameTime: Double? = nil,
        cineRate: Int? = nil,
        recommendedDisplayFrameRate: Int? = nil,
        frameDelay: Double? = nil,
        actualFrameDuration: Int? = nil,
        startTrim: Int? = nil,
        stopTrim: Int? = nil,
        frameTimeVector: [Double]? = nil,
        preferredPlaybackSequencing: Int? = nil,
        imageTriggerDelay: Double? = nil,
        effectiveDuration: Double? = nil,
        multiplexedAudioChannels: [VideoAudioChannel] = [],
        contentDate: DICOMDate? = nil,
        contentTime: DICOMTime? = nil,
        lossyImageCompression: String? = nil,
        lossyImageCompressionRatio: Double? = nil,
        lossyImageCompressionMethod: String? = nil,
        imageType: [String] = Video.defaultImageType,
        manufacturer: String? = nil,
        manufacturerModelName: String? = nil,
        deviceSerialNumber: String? = nil,
        softwareVersions: String? = nil,
        institutionName: String? = nil,
        acquisitionDate: DICOMDate? = nil,
        acquisitionTime: DICOMTime? = nil,
        patientOrientation: String? = nil,
        studyDate: DICOMDate? = nil,
        studyTime: DICOMTime? = nil,
        referringPhysicianName: String? = nil,
        studyID: String? = nil,
        accessionNumber: String? = nil,
        patientBirthDate: DICOMDate? = nil,
        patientSex: String? = nil,
        pixelData: Data? = nil,
        stereoPairsPresent: Bool? = nil,
        allowsMultipleFragments: Bool = false
    ) {
        self.stereoPairsPresent = stereoPairsPresent
        self.allowsMultipleFragments = allowsMultipleFragments
        self.sopInstanceUID = sopInstanceUID
        self.sopClassUID = sopClassUID
        self.studyInstanceUID = studyInstanceUID
        self.seriesInstanceUID = seriesInstanceUID
        self.instanceNumber = instanceNumber
        self.patientName = patientName
        self.patientID = patientID
        self.modality = modality
        self.seriesDescription = seriesDescription
        self.seriesNumber = seriesNumber
        self.rows = rows
        self.columns = columns
        self.numberOfFrames = numberOfFrames
        self.samplesPerPixel = samplesPerPixel
        self.photometricInterpretation = photometricInterpretation
        self.bitsAllocated = bitsAllocated
        self.bitsStored = bitsStored
        self.highBit = highBit
        self.pixelRepresentation = pixelRepresentation
        self.planarConfiguration = planarConfiguration
        self.frameTime = frameTime
        self.cineRate = cineRate
        self.recommendedDisplayFrameRate = recommendedDisplayFrameRate
        self.frameDelay = frameDelay
        self.actualFrameDuration = actualFrameDuration
        self.startTrim = startTrim
        self.stopTrim = stopTrim
        self.frameTimeVector = frameTimeVector
        self.preferredPlaybackSequencing = preferredPlaybackSequencing
        self.imageTriggerDelay = imageTriggerDelay
        self.effectiveDuration = effectiveDuration
        self.multiplexedAudioChannels = multiplexedAudioChannels
        self.contentDate = contentDate
        self.contentTime = contentTime
        self.lossyImageCompression = lossyImageCompression
        self.lossyImageCompressionRatio = lossyImageCompressionRatio
        self.lossyImageCompressionMethod = lossyImageCompressionMethod
        self.imageType = imageType
        self.manufacturer = manufacturer
        self.manufacturerModelName = manufacturerModelName
        self.deviceSerialNumber = deviceSerialNumber
        self.softwareVersions = softwareVersions
        self.institutionName = institutionName
        self.acquisitionDate = acquisitionDate
        self.acquisitionTime = acquisitionTime
        self.patientOrientation = patientOrientation
        self.studyDate = studyDate
        self.studyTime = studyTime
        self.referringPhysicianName = referringPhysicianName
        self.studyID = studyID
        self.accessionNumber = accessionNumber
        self.patientBirthDate = patientBirthDate
        self.patientSex = patientSex
        self.pixelData = pixelData
    }

    /// The video type inferred from the SOP Class UID
    public var videoType: VideoType {
        return VideoType(sopClassUID: sopClassUID)
    }

    /// The effective frame rate in frames/second
    ///
    /// Returns the recommended display frame rate if available, then cine rate,
    /// then computes from frame time. Defaults to 30 fps.
    public var effectiveFrameRate: Double {
        if let rate = recommendedDisplayFrameRate {
            return Double(rate)
        }
        if let rate = cineRate {
            return Double(rate)
        }
        if let ft = frameTime, ft > 0 {
            return 1000.0 / ft
        }
        return 30.0
    }

    /// The total duration of the video in seconds
    public var duration: Double {
        return Double(numberOfFrames) / effectiveFrameRate
    }

    /// The video resolution as a string (e.g., "1920x1080")
    public var resolution: String {
        return "\(columns)x\(rows)"
    }

    /// Whether this is an endoscopic video
    public var isEndoscopic: Bool {
        return sopClassUID == Self.videoEndoscopicImageStorageUID
    }

    /// Whether this is a microscopic video
    public var isMicroscopic: Bool {
        return sopClassUID == Self.videoMicroscopicImageStorageUID
    }

    /// Whether this is a photographic video
    public var isPhotographic: Bool {
        return sopClassUID == Self.videoPhotographicImageStorageUID
    }
}

// MARK: - Video Type

/// Type of video based on SOP Class UID
public enum VideoType: String, Sendable {
    /// Video from endoscopic procedures
    case endoscopic

    /// Video from microscopic imaging
    case microscopic

    /// Video from photographic equipment
    case photographic

    /// Unknown or unrecognized video type
    case unknown

    /// Creates a video type from a SOP Class UID
    public init(sopClassUID: String) {
        switch sopClassUID {
        case Video.videoEndoscopicImageStorageUID:
            self = .endoscopic
        case Video.videoMicroscopicImageStorageUID:
            self = .microscopic
        case Video.videoPhotographicImageStorageUID:
            self = .photographic
        default:
            self = .unknown
        }
    }

    /// The SOP Class UID for this video type
    public var sopClassUID: String {
        switch self {
        case .endoscopic: return Video.videoEndoscopicImageStorageUID
        case .microscopic: return Video.videoMicroscopicImageStorageUID
        case .photographic: return Video.videoPhotographicImageStorageUID
        case .unknown: return ""
        }
    }

    /// The default modality for this video type
    public var defaultModality: String {
        switch self {
        case .endoscopic: return Modality.es.rawValue
        case .microscopic: return Modality.gm.rawValue
        case .photographic: return Modality.xc.rawValue
        case .unknown: return Modality.ot.rawValue
        }
    }

    /// Human-readable description of the video type
    public var displayName: String {
        switch self {
        case .endoscopic: return "Video Endoscopic"
        case .microscopic: return "Video Microscopic"
        case .photographic: return "Video Photographic"
        case .unknown: return "Unknown Video"
        }
    }
}

// MARK: - Video Codec

/// Video compression codec type
public enum VideoCodec: String, Sendable {
    /// MPEG-2 video compression
    case mpeg2

    /// H.264/AVC video compression
    case h264

    /// H.265/HEVC video compression
    case h265

    /// Unknown or unrecognized codec
    case unknown

    /// Creates a video codec from a transfer syntax UID
    ///
    /// Recognizes all 20 registered video transfer syntaxes, including the
    /// H.264 Level 4.2 UIDs and every fragmentable "….1" variant.
    public init(transferSyntaxUID: String) {
        guard let ts = TransferSyntax.from(uid: transferSyntaxUID) else {
            self = .unknown
            return
        }
        if ts.isMPEG2 {
            self = .mpeg2
        } else if ts.isH264 {
            self = .h264
        } else if ts.isH265 {
            self = .h265
        } else {
            self = .unknown
        }
    }

    /// The Lossy Image Compression Method (0028,2114) Defined Term for this codec.
    ///
    /// PS3.3 C.7.6.1.1.5.1 Defined Terms: `ISO_13818_2` (MPEG2 Video), `ISO_14496_10`
    /// (MPEG-4 AVC/H.264), `ISO_23008_2` (HEVC/H.265). An unknown codec has no term
    /// and yields an empty string; ``Video/toDataSet()`` never writes that.
    public var compressionMethod: String {
        switch self {
        case .mpeg2: return "ISO_13818_2"
        case .h264: return "ISO_14496_10"
        case .h265: return "ISO_23008_2"
        case .unknown: return ""
        }
    }

    /// The Lossy Image Compression Method term for a transfer syntax UID, or nil
    /// when the UID is not one of the video transfer syntaxes of PS3.6 Table A-1.
    public static func compressionMethod(forTransferSyntaxUID uid: String) -> String? {
        let codec = VideoCodec(transferSyntaxUID: uid)
        return codec == .unknown ? nil : codec.compressionMethod
    }

    /// Human-readable display name
    public var displayName: String {
        switch self {
        case .mpeg2: return "MPEG-2"
        case .h264: return "H.264/AVC"
        case .h265: return "H.265/HEVC"
        case .unknown: return "Unknown"
        }
    }
}

// MARK: - Multiplexed Audio

/// One Item of Multiplexed Audio Channels Description Code Sequence (003A,0300),
/// PS3.3 Table C.7-13.
public struct VideoAudioChannel: Sendable, Equatable {
    /// Channel Mode (003A,0302), Type 1. Enumerated Values: MONO ("1 signal"),
    /// STEREO ("2 simultaneously acquired (left and right) signals").
    public enum Mode: String, Sendable {
        case mono = "MONO"
        case stereo = "STEREO"
    }

    /// The one Item of Channel Source Sequence (003A,0208), Type 1: any coded
    /// concept (PS3.3 Table 8.8-1 Code Sequence Macro).
    ///
    /// PS3.3 2026a Table C.7-13 includes the macro with "DCID 3000", and PS3.16
    /// 2026a CID 3000 Audio Channel Source is "Type: Extensible" (Version
    /// 20040326), so a file may carry a code outside its six members. `Source`
    /// therefore wraps any ``CodedConcept``; the CID 3000 members are static
    /// constants, and ``isCID3000Member`` tells them apart (D57).
    ///
    /// Two sources are equal when Coding Scheme Designator and Code Value (or
    /// Long Code Value / URN Code Value) match; Code Meaning and Coding Scheme
    /// Version do not take part.
    public struct Source: Sendable, Hashable, CustomStringConvertible {
        /// The code as read from, or to be written to, the Item.
        public let code: CodedConcept

        public init(_ code: CodedConcept) {
            self.code = code
        }

        /// A DCM code, for example one of CID 3000's.
        public init(dcmCodeValue codeValue: String, codeMeaning: String) {
            self.code = CodedConcept(codeValue: codeValue, codingSchemeDesignator: "DCM",
                                     codeMeaning: codeMeaning)
        }

        /// Code Value (0008,0100), or the Long / URN Code Value when that is how
        /// the code was given.
        public var codeValue: String { code.codeValue }
        /// Coding Scheme Designator (0008,0102).
        public var codingSchemeDesignator: String { code.codingSchemeDesignator }
        /// Code Meaning (0008,0104).
        public var codeMeaning: String { code.codeMeaning }
        public var description: String { "(\(codeValue), \(codingSchemeDesignator), \"\(codeMeaning)\")" }

        // PS3.16 2026a CID 3000 Audio Channel Source, all DCM, Code Meaning as listed.
        /// (109110, DCM, "Voice")
        public static let voice = Source(dcmCodeValue: "109110", codeMeaning: "Voice")
        /// (109111, DCM, "Operator's narrative")
        public static let operatorsNarrative = Source(dcmCodeValue: "109111", codeMeaning: "Operator's narrative")
        /// (109112, DCM, "Ambient room environment")
        public static let ambientRoomEnvironment = Source(dcmCodeValue: "109112", codeMeaning: "Ambient room environment")
        /// (109113, DCM, "Doppler audio")
        public static let dopplerAudio = Source(dcmCodeValue: "109113", codeMeaning: "Doppler audio")
        /// (109114, DCM, "Phonocardiogram")
        public static let phonocardiogram = Source(dcmCodeValue: "109114", codeMeaning: "Phonocardiogram")
        /// (109115, DCM, "Physiological audio signal")
        public static let physiologicalAudioSignal = Source(dcmCodeValue: "109115", codeMeaning: "Physiological audio signal")

        /// The six members of PS3.16 2026a CID 3000, in table order.
        public static let cid3000: [Source] = [
            .voice, .operatorsNarrative, .ambientRoomEnvironment,
            .dopplerAudio, .phonocardiogram, .physiologicalAudioSignal,
        ]

        /// Whether the code is one of CID 3000's (DCM 109110–109115). A code
        /// outside it is still valid: the CID is Extensible.
        public var isCID3000Member: Bool { Self.cid3000.contains(self) }

        /// The CID 3000 constant with this code's identity, so a parsed code
        /// can be matched against the known members regardless of its meaning.
        public var cid3000Member: Source? { Self.cid3000.first { $0 == self } }

        public static func == (lhs: Source, rhs: Source) -> Bool {
            lhs.identity == rhs.identity
        }

        public func hash(into hasher: inout Hasher) {
            hasher.combine(identity.designator)
            hasher.combine(identity.value)
        }

        private var identity: (designator: String, value: String) {
            let value = code.urnCodeValue ?? code.longCodeValue ?? code.codeValue
            return (code.codingSchemeDesignator.trimmingCharacters(in: .whitespaces),
                    value.trimmingCharacters(in: .whitespaces))
        }
    }

    /// Channel Identification Code (003A,0301), Type 1 — "1 for the main channel, 2
    /// for the second channel and 3 to 9 to the complementary channels".
    public let channelIdentificationCode: Int
    /// Channel Mode (003A,0302), Type 1.
    public let mode: Mode
    /// Channel Source Sequence (003A,0208), Type 1, "Only a single Item": any
    /// code, CID 3000 being Extensible.
    public let source: Source

    public init(channelIdentificationCode: Int, mode: Mode, source: Source) {
        self.channelIdentificationCode = channelIdentificationCode
        self.mode = mode
        self.source = source
    }

    /// Multiplexed Audio Channels Description Code Sequence (003A,0300).
    static let multiplexedAudioChannelsDescriptionCodeSequence = Tag(group: 0x003A, element: 0x0300)
    /// Channel Identification Code (003A,0301), VR IS.
    static let channelIdentificationCodeTag = Tag(group: 0x003A, element: 0x0301)
    /// Channel Mode (003A,0302), VR CS.
    static let channelModeTag = Tag(group: 0x003A, element: 0x0302)
}

// MARK: - Bit Depth

/// The DICOM bit-depth triple for a coded video profile.
///
/// DICOM allocates pixel storage on byte boundaries, so a 10-bit stream is
/// `BitsAllocated` 16 rather than 10.
///
/// Reference: PS3.5 Sections 8.2.7, 8.2.10, 8.2.11
public struct VideoBitDepth: Sendable, Hashable {
    /// Bits Allocated (0028,0100)
    public let bitsAllocated: Int
    /// Bits Stored (0028,0101)
    public let bitsStored: Int
    /// High Bit (0028,0102)
    public let highBit: Int

    public init(bitsAllocated: Int, bitsStored: Int, highBit: Int) {
        self.bitsAllocated = bitsAllocated
        self.bitsStored = bitsStored
        self.highBit = highBit
    }

    /// 8-bit video: MPEG-2, H.264 High Profile, and HEVC Main.
    public static let eightBit = VideoBitDepth(bitsAllocated: 8, bitsStored: 8, highBit: 7)

    /// 10-bit video: HEVC Main 10. Allocated on a 16-bit boundary per PS3.5 8.2.11.
    public static let tenBit = VideoBitDepth(bitsAllocated: 16, bitsStored: 10, highBit: 9)

    /// The DICOM bit depth for a coded luma bit depth.
    ///
    /// Only 8-bit and 10-bit are representable by the DICOM video transfer syntaxes;
    /// any other depth returns nil so callers reject rather than silently mislabel.
    public static func forLumaBitDepth(_ bitDepth: Int) -> VideoBitDepth? {
        switch bitDepth {
        case 8: return .eightBit
        case 10: return .tenBit
        default: return nil
        }
    }
}
