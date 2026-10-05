//
// VideoLevelLimits.swift
// DICOMKit
//
// Copyright © 2026 DICOMKit. All rights reserved.
//

import Foundation

/// The picture-size and throughput limits a codec level imposes.
///
/// PS3.5 requires Rows, Columns and the frame rate to be "compliant with" the
/// transfer syntax's profile and level - not merely that the stream's
/// `level_idc` be low enough. A stream can claim Level 4.1 while coding 4K
/// pictures (x264 warns and writes it anyway), so the claim is checked against
/// what the stream actually codes.
///
/// Reference: ITU-T H.264 Table A-1, ITU-T H.265 Table A.8 (Main tier)
public enum VideoLevelLimits {

    /// The limits of one level.
    public struct Limits: Sendable, Hashable {
        /// Maximum picture size: macroblocks (H.264) or luma samples (HEVC).
        public let maxPictureSize: Int
        /// Maximum throughput: macroblocks (H.264) or luma samples (HEVC) per second.
        public let maxThroughput: Int
        /// Maximum width or height in the same unit as a picture side:
        /// macroblocks (H.264) or luma samples (HEVC), i.e. sqrt(8 * maxPictureSize).
        public var maxDimension: Int { Int((8.0 * Double(maxPictureSize)).squareRoot()) }
    }

    /// H.264 Table A-1: (MaxMBPS, MaxFS) by level times ten.
    private static let h264: [Int: Limits] = [
        10: Limits(maxPictureSize: 99, maxThroughput: 1_485),
        11: Limits(maxPictureSize: 396, maxThroughput: 3_000),
        12: Limits(maxPictureSize: 396, maxThroughput: 6_000),
        13: Limits(maxPictureSize: 396, maxThroughput: 11_880),
        20: Limits(maxPictureSize: 396, maxThroughput: 11_880),
        21: Limits(maxPictureSize: 792, maxThroughput: 19_800),
        22: Limits(maxPictureSize: 1_620, maxThroughput: 20_250),
        30: Limits(maxPictureSize: 1_620, maxThroughput: 40_500),
        31: Limits(maxPictureSize: 3_600, maxThroughput: 108_000),
        32: Limits(maxPictureSize: 5_120, maxThroughput: 216_000),
        40: Limits(maxPictureSize: 8_192, maxThroughput: 245_760),
        41: Limits(maxPictureSize: 8_192, maxThroughput: 245_760),
        42: Limits(maxPictureSize: 8_704, maxThroughput: 522_240),
        50: Limits(maxPictureSize: 22_080, maxThroughput: 589_824),
        51: Limits(maxPictureSize: 36_864, maxThroughput: 983_040),
        52: Limits(maxPictureSize: 36_864, maxThroughput: 2_073_600),
        60: Limits(maxPictureSize: 139_264, maxThroughput: 4_177_920),
        61: Limits(maxPictureSize: 139_264, maxThroughput: 8_355_840),
        62: Limits(maxPictureSize: 139_264, maxThroughput: 16_711_680),
    ]

    /// H.265 Table A.8, Main tier: (MaxLumaPs, MaxLumaSr) by level times ten.
    private static let hevc: [Int: Limits] = [
        10: Limits(maxPictureSize: 36_864, maxThroughput: 552_960),
        20: Limits(maxPictureSize: 122_880, maxThroughput: 3_686_400),
        21: Limits(maxPictureSize: 245_760, maxThroughput: 7_372_800),
        30: Limits(maxPictureSize: 552_960, maxThroughput: 16_588_800),
        31: Limits(maxPictureSize: 983_040, maxThroughput: 33_177_600),
        40: Limits(maxPictureSize: 2_228_224, maxThroughput: 66_846_720),
        41: Limits(maxPictureSize: 2_228_224, maxThroughput: 133_693_440),
        50: Limits(maxPictureSize: 8_912_896, maxThroughput: 267_386_880),
        51: Limits(maxPictureSize: 8_912_896, maxThroughput: 534_773_760),
        52: Limits(maxPictureSize: 8_912_896, maxThroughput: 1_069_547_520),
        60: Limits(maxPictureSize: 35_651_584, maxThroughput: 1_069_547_520),
        61: Limits(maxPictureSize: 35_651_584, maxThroughput: 2_139_095_040),
        62: Limits(maxPictureSize: 35_651_584, maxThroughput: 4_278_190_080),
    ]

    /// The limits of a level, or nil for a codec or level without a table.
    public static func limits(codec: VideoCodec, levelTimesTen: Int) -> Limits? {
        switch codec {
        case .h264: return h264[levelTimesTen]
        case .h265: return hevc[levelTimesTen]
        case .mpeg2, .unknown: return nil
        }
    }

    /// One way a stream exceeds a level.
    public enum Excess: Sendable, Hashable {
        /// The picture is larger than the level allows.
        case pictureSize(observed: Int, maximum: Int, unit: String)
        /// One side of the picture is longer than the level allows.
        case dimension(observed: Int, maximum: Int, unit: String)
        /// Pictures per second times picture size exceeds the level's rate.
        case throughput(observed: Int, maximum: Int, unit: String)

        /// A clause for a rejection message.
        public var description: String {
            switch self {
            case let .pictureSize(observed, maximum, unit):
                return "\(observed) \(unit) per picture exceeds the maximum of \(maximum)"
            case let .dimension(observed, maximum, unit):
                return "a picture side of \(observed) \(unit) exceeds the maximum of \(maximum)"
            case let .throughput(observed, maximum, unit):
                return "\(observed) \(unit) per second exceeds the maximum of \(maximum)"
            }
        }
    }

    /// How a stream's coded geometry and frame rate exceed a level, or empty
    /// when they fit.
    ///
    /// Uses the coded size (before cropping) where the stream summary has it,
    /// since that is what the limits are defined over; falls back to the
    /// display size rounded up to the coding unit.
    public static func excesses(of stream: VideoStreamInfo, levelTimesTen: Int) -> [Excess] {
        guard let limits = limits(codec: stream.codec, levelTimesTen: levelTimesTen) else { return [] }

        let width: Int
        let height: Int
        let unit: String
        switch stream.codec {
        case .h264:
            let codedWidth = stream.codedWidth ?? roundUp(stream.width, to: 16)
            let codedHeight = stream.codedHeight ?? roundUp(stream.height, to: stream.isProgressive ? 16 : 32)
            width = codedWidth / 16
            height = codedHeight / 16
            unit = "macroblocks"
        case .h265:
            width = stream.codedWidth ?? roundUp(stream.width, to: 8)
            height = stream.codedHeight ?? roundUp(stream.height, to: 8)
            unit = "luma samples"
        case .mpeg2, .unknown:
            return []
        }

        var excesses: [Excess] = []
        let size = width * height
        if size > limits.maxPictureSize {
            excesses.append(.pictureSize(observed: size, maximum: limits.maxPictureSize, unit: unit))
        }
        let side = max(width, height)
        if side > limits.maxDimension {
            excesses.append(.dimension(observed: side, maximum: limits.maxDimension, unit: unit))
        }
        if let rate = stream.frameRate, rate > 0 {
            let throughput = Int((Double(size) * rate).rounded())
            // A whisker of tolerance for 30000/1001-style rates derived from
            // container durations.
            if Double(throughput) > Double(limits.maxThroughput) * 1.001 {
                excesses.append(.throughput(observed: throughput, maximum: limits.maxThroughput, unit: unit))
            }
        }
        return excesses
    }

    private static func roundUp(_ value: Int, to multiple: Int) -> Int {
        (value + multiple - 1) / multiple * multiple
    }
}
