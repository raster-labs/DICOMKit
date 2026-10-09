// NEMA-verified: 2026a, checked 2026-10-01 — carries codec parameters only; the DICOM constraints are checked in VideoConformanceValidator; MPEG-2 levels named Main / High (High 1440, Low) as PS3.5 2026a 8.2.5 / 8.2.6 name them (D178)
//
// VideoStreamInfo.swift
// DICOMKit
//
// Copyright © 2026 DICOMKit. All rights reserved.
//

import Foundation

/// Chroma subsampling, as coded by `chroma_format_idc`.
///
/// Every DICOM video transfer syntax requires 4:2:0 (PS3.5 8.2.7 / 8.2.10 /
/// 8.2.11), so the other cases exist to be *reported* in a rejection, not carried.
public enum ChromaFormat: Int, Sendable, Hashable {
    /// Monochrome, no chroma planes.
    case monochrome = 0
    /// 4:2:0 — the only format the DICOM video transfer syntaxes permit.
    case yuv420 = 1
    /// 4:2:2.
    case yuv422 = 2
    /// 4:4:4.
    case yuv444 = 3

    /// A human-readable name for error messages.
    public var displayName: String {
        switch self {
        case .monochrome: return "monochrome"
        case .yuv420: return "4:2:0"
        case .yuv422: return "4:2:2"
        case .yuv444: return "4:4:4"
        }
    }
}

/// What a coded video bit stream says about itself.
///
/// Every field is read from the coded parameter sets rather than supplied by the
/// caller, so that the DICOM attributes cannot contradict the pixel data they
/// describe.
public struct VideoStreamInfo: Sendable, Hashable {

    /// The codec the stream is coded in.
    public let codec: VideoCodec

    /// Display width in luma samples, after cropping / the conformance window.
    public let width: Int

    /// Display height in luma samples, after cropping / the conformance window.
    public let height: Int

    /// `profile_idc` (H.264) or `general_profile_idc` (HEVC); the MPEG-2 profile
    /// identifier for MPEG-2.
    public let profileIDC: Int

    /// `level_idc` (H.264) or `general_level_idc` (HEVC), in units of one tenth of
    /// a level: level 4.1 is 41, level 5.1 is 51.
    ///
    /// H.264 codes this as level times 10 already; HEVC codes it as level times 30,
    /// and the parser normalizes it here so callers can compare uniformly.
    public let levelTimesTen: Int

    /// Chroma subsampling.
    public let chromaFormat: ChromaFormat

    /// Coded luma bit depth: 8 for MPEG-2, H.264 High and HEVC Main; 10 for HEVC
    /// Main 10.
    public let bitDepthLuma: Int

    /// Coded chroma bit depth.
    public let bitDepthChroma: Int

    /// Frame rate in frames per second, when the stream declares one.
    ///
    /// H.264 and HEVC carry this only in an optional VUI block, so it is absent for
    /// streams that omit VUI timing information.
    public let frameRate: Double?

    /// Whether the stream is coded progressively.
    public let isProgressive: Bool

    /// The sample (pixel) aspect ratio as width:height, when the stream declares
    /// one. `nil` means the stream declares no ratio, which is read as 1:1.
    ///
    /// DICOM requires SAR 1:1, since Pixel Aspect Ratio must be absent
    /// (PS3.5 8.2.7). Anything else has to be rejected.
    public let sampleAspectRatio: (width: Int, height: Int)?

    /// Coded picture width in luma samples, before cropping, when known.
    ///
    /// Level limits are defined on the coded picture, not the displayed one: a
    /// 1920x1080 H.264 stream codes 1088 rows, and it is those 68 macroblock rows
    /// that count against `MaxFS`. Nil for MPEG-2, whose header carries only the
    /// display size, and for summaries built without a parameter set.
    public let codedWidth: Int?

    /// Coded frame height in luma samples, before cropping, when known.
    public let codedHeight: Int?

    /// Whether an HEVC stream is coded at High tier (`general_tier_flag` = 1).
    ///
    /// PS3.5 8.2.10 and 8.2.11 name Main tier, so High tier is rejected. Always
    /// false for the other codecs, which have no tiers.
    public let isHighTier: Bool

    /// Whether the stream carries an H.264 frame packing arrangement SEI, i.e.
    /// packs two views into each frame for 3D display.
    ///
    /// Nil when the coded pictures were not inspected. PS3.5 Table 8-8 requires
    /// the SEI for the "For 3D Video" transfer syntax and forbids it for
    /// "For 2D Video".
    public let hasFramePacking: Bool?

    /// MPEG-2 `aspect_ratio_information` (ITU-T H.262 Table 6-3): 1 is square
    /// samples, 2 is 4:3, 3 is 16:9 and 4 is 2.21:1 display aspect ratio.
    ///
    /// PS3.5 8.2.6 requires 3 (16:9) for Main Profile / High Level.
    public let mpeg2AspectRatioInformation: Int?

    /// Whether the sample aspect ratio is square, i.e. SAR 1:1.
    public var hasSquarePixels: Bool {
        guard let ratio = sampleAspectRatio else { return true }
        return ratio.width == ratio.height
    }

    /// The level as a decimal number, e.g. 4.1 or 5.1. For MPEG-2, which has named
    /// levels rather than numbered ones, this is the raw `level_identification` / 10;
    /// use ``levelDescription``.
    public var level: Double { Double(levelTimesTen) / 10.0 }

    /// A short human-readable level: "4.1" for H.264/HEVC; for MPEG-2 the ISO/IEC
    /// 13818-2 level name ("Main", "High", "High 1440", "Low"), the names PS3.5 2026a
    /// 8.2.5 / 8.2.6 use ("Main Profile / Main Level", "Main Profile / High Level").
    public var levelDescription: String {
        if codec == .mpeg2 { return Self.mpeg2LevelName(levelTimesTen) }
        let whole = levelTimesTen / 10
        let fraction = levelTimesTen % 10
        return "\(whole).\(fraction)"
    }

    /// Names an MPEG-2 `level_identification` value (ISO/IEC 13818-2 Table 8-11).
    static func mpeg2LevelName(_ identifier: Int) -> String {
        switch identifier {
        case 10: return "Low"
        case 8: return "Main"
        case 6: return "High 1440"
        case 4: return "High"
        default: return "level_identification \(identifier)"
        }
    }

    public init(
        codec: VideoCodec,
        width: Int,
        height: Int,
        profileIDC: Int,
        levelTimesTen: Int,
        chromaFormat: ChromaFormat,
        bitDepthLuma: Int,
        bitDepthChroma: Int,
        frameRate: Double?,
        isProgressive: Bool,
        sampleAspectRatio: (width: Int, height: Int)? = nil,
        codedWidth: Int? = nil,
        codedHeight: Int? = nil,
        isHighTier: Bool = false,
        hasFramePacking: Bool? = nil,
        mpeg2AspectRatioInformation: Int? = nil
    ) {
        self.mpeg2AspectRatioInformation = mpeg2AspectRatioInformation
        self.codec = codec
        self.width = width
        self.height = height
        self.profileIDC = profileIDC
        self.levelTimesTen = levelTimesTen
        self.chromaFormat = chromaFormat
        self.bitDepthLuma = bitDepthLuma
        self.bitDepthChroma = bitDepthChroma
        self.frameRate = frameRate
        self.isProgressive = isProgressive
        self.sampleAspectRatio = sampleAspectRatio
        self.codedWidth = codedWidth
        self.codedHeight = codedHeight
        self.isHighTier = isHighTier
        self.hasFramePacking = hasFramePacking
    }

    /// A copy with some fields replaced, so callers that refine one fact - a
    /// container's frame rate, a scan's frame packing verdict - cannot drop the
    /// others by rebuilding the summary field by field.
    public func with(
        frameRate: Double?? = nil,
        profileIDC: Int? = nil,
        levelTimesTen: Int? = nil,
        hasFramePacking: Bool?? = nil
    ) -> VideoStreamInfo {
        VideoStreamInfo(
            codec: codec,
            width: width,
            height: height,
            profileIDC: profileIDC ?? self.profileIDC,
            levelTimesTen: levelTimesTen ?? self.levelTimesTen,
            chromaFormat: chromaFormat,
            bitDepthLuma: bitDepthLuma,
            bitDepthChroma: bitDepthChroma,
            frameRate: frameRate ?? self.frameRate,
            isProgressive: isProgressive,
            sampleAspectRatio: sampleAspectRatio,
            codedWidth: codedWidth,
            codedHeight: codedHeight,
            isHighTier: isHighTier,
            hasFramePacking: hasFramePacking ?? self.hasFramePacking,
            mpeg2AspectRatioInformation: mpeg2AspectRatioInformation
        )
    }

    public static func == (lhs: VideoStreamInfo, rhs: VideoStreamInfo) -> Bool {
        return lhs.codec == rhs.codec
            && lhs.width == rhs.width
            && lhs.height == rhs.height
            && lhs.profileIDC == rhs.profileIDC
            && lhs.levelTimesTen == rhs.levelTimesTen
            && lhs.chromaFormat == rhs.chromaFormat
            && lhs.bitDepthLuma == rhs.bitDepthLuma
            && lhs.bitDepthChroma == rhs.bitDepthChroma
            && lhs.frameRate == rhs.frameRate
            && lhs.isProgressive == rhs.isProgressive
            && lhs.sampleAspectRatio?.width == rhs.sampleAspectRatio?.width
            && lhs.sampleAspectRatio?.height == rhs.sampleAspectRatio?.height
            && lhs.codedWidth == rhs.codedWidth
            && lhs.codedHeight == rhs.codedHeight
            && lhs.isHighTier == rhs.isHighTier
            && lhs.hasFramePacking == rhs.hasFramePacking
            && lhs.mpeg2AspectRatioInformation == rhs.mpeg2AspectRatioInformation
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(codec)
        hasher.combine(width)
        hasher.combine(height)
        hasher.combine(profileIDC)
        hasher.combine(levelTimesTen)
        hasher.combine(chromaFormat)
        hasher.combine(bitDepthLuma)
        hasher.combine(bitDepthChroma)
        hasher.combine(frameRate)
        hasher.combine(isProgressive)
        hasher.combine(sampleAspectRatio?.width)
        hasher.combine(sampleAspectRatio?.height)
        hasher.combine(codedWidth)
        hasher.combine(codedHeight)
        hasher.combine(isHighTier)
        hasher.combine(hasFramePacking)
        hasher.combine(mpeg2AspectRatioInformation)
    }
}

// MARK: - H.264 Profile Names

extension VideoStreamInfo {
    /// A human-readable profile name for error messages.
    ///
    /// Rejections have to name the observed profile, and "profile_idc 66" means
    /// much less to a user than "Baseline".
    public var profileName: String {
        switch codec {
        case .h264:
            switch profileIDC {
            case 66: return "Baseline"
            case 77: return "Main"
            case 88: return "Extended"
            case 100: return "High"
            case 110: return "High 10"
            case 122: return "High 4:2:2"
            case 244: return "High 4:4:4 Predictive"
            case 128: return "Stereo High"
            case 118: return "Multiview High"
            case 44: return "CAVLC 4:4:4 Intra"
            default: return "profile_idc \(profileIDC)"
            }
        case .h265:
            switch profileIDC {
            case 1: return "Main"
            case 2: return "Main 10"
            case 3: return "Main Still Picture"
            case 4: return "Format Range Extensions"
            default: return "profile_idc \(profileIDC)"
            }
        case .mpeg2:
            switch profileIDC {
            case 5: return "Simple"
            case 4: return "Main"
            case 3: return "SNR Scalable"
            case 2: return "Spatially Scalable"
            case 1: return "High"
            default: return "profile \(profileIDC)"
            }
        case .unknown:
            return "profile \(profileIDC)"
        }
    }
}
