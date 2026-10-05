// NEMA-verified: 2026a, checked 2026-09-29 — MPEG2 transfer syntax UIDs .100/.101 match PS3.6 2026a Table A-1; the bitstream syntax is ITU-T H.262 (out of scope)
//
// MPEG2Parser.swift
// DICOMKit
//
// Copyright © 2026 DICOMKit. All rights reserved.
//

import Foundation

/// Parses MPEG-2 sequence headers.
///
/// MPEG-2 is byte-code oriented rather than NAL oriented: the parameters live in a
/// sequence header identified by a start code, optionally extended by a sequence
/// extension that widens the size and frame-rate fields.
///
/// Reference: ITU-T H.262 Sections 6.2.2.1 (sequence_header) and 6.2.2.3
/// (sequence_extension)
public enum MPEG2Parser {

    // MARK: - Start Codes

    /// Sequence header start code (0x000001B3).
    public static let sequenceHeaderCode: UInt8 = 0xB3
    /// Extension start code (0x000001B5).
    public static let extensionStartCode: UInt8 = 0xB5
    /// Picture start code (0x00000100).
    public static let pictureStartCode: UInt8 = 0x00
    /// Group of pictures start code (0x000001B8).
    public static let groupStartCode: UInt8 = 0xB8

    // MARK: - Sequence Header

    /// The fields of an MPEG-2 sequence header this toolkit needs.
    public struct SequenceHeader: Sendable, Hashable {
        public let width: Int
        public let height: Int
        /// Frame rate in frames per second, from `frame_rate_code` and, when a
        /// sequence extension is present, its numerator/denominator extensions.
        public let frameRate: Double
        /// `aspect_ratio_information`, per ITU-T H.262 Table 6-3.
        public let aspectRatioInformation: Int
        /// `profile_and_level_indication` from the sequence extension, when present.
        public let profileAndLevel: Int?
        /// Whether the sequence extension declares a progressive sequence.
        public let isProgressive: Bool
        /// `chroma_format` from the sequence extension: 1 is 4:2:0, 2 is 4:2:2,
        /// 3 is 4:4:4. Defaults to 4:2:0, which is all MPEG-1-style headers allow.
        public let chromaFormat: Int

        /// `profile_and_level_indication` decodes as an escape bit, a 3-bit profile
        /// and a 4-bit level.
        public var profileIdentifier: Int? {
            guard let value = profileAndLevel else { return nil }
            return (value >> 4) & 0x07
        }

        /// The level identifier from `profile_and_level_indication`.
        ///
        /// Per ITU-T H.262 Table 8-11, identifiers *descend* as levels rise: 4 is
        /// High, 6 is High 1440, 8 is Main and 10 is Low.
        public var levelIdentifier: Int? {
            guard let value = profileAndLevel else { return nil }
            return value & 0x0F
        }

        /// Whether this is Main Profile at Main Level, the constraint of
        /// transfer syntax 1.2.840.10008.1.2.4.100.
        public var isMainProfileMainLevel: Bool {
            profileIdentifier == 4 && levelIdentifier == 8
        }

        /// Whether this is Main Profile at High Level, the constraint of
        /// transfer syntax 1.2.840.10008.1.2.4.101.
        public var isMainProfileHighLevel: Bool {
            profileIdentifier == 4 && levelIdentifier == 4
        }
    }

    /// `frame_rate_code` to frames per second, per ITU-T H.262 Table 6-4.
    ///
    /// Index 0 is forbidden; indices 9-15 are reserved.
    static let frameRateTable: [Double?] = [
        nil,              // 0: forbidden
        24000.0 / 1001.0, // 1: 23.976
        24.0,             // 2
        25.0,             // 3
        30000.0 / 1001.0, // 4: 29.97
        30.0,             // 5
        50.0,             // 6
        60000.0 / 1001.0, // 7: 59.94
        60.0,             // 8
        nil, nil, nil, nil, nil, nil, nil,
    ]

    // MARK: - Parsing

    /// Parses the first sequence header in an MPEG-2 elementary stream.
    ///
    /// - Parameter data: An MPEG-2 video elementary stream.
    /// - Returns: The parsed header, or nil if no valid sequence header is found.
    public static func parseSequenceHeader(_ data: Data) -> SequenceHeader? {
        let bytes = [UInt8](data)
        guard let headerStart = findStartCode(bytes, code: sequenceHeaderCode, from: 0) else {
            return nil
        }

        // sequence_header: 12-bit width, 12-bit height, 4-bit aspect ratio,
        // 4-bit frame rate code, 18-bit bit rate, marker, 10-bit VBV buffer size,
        // constrained flag, then the optional quantiser matrices.
        let payloadStart = headerStart + 4
        guard payloadStart + 8 <= bytes.count else { return nil }

        var reader = BitstreamReader(bytes: Array(bytes[payloadStart...]))
        guard let widthValue = reader.readBits(12),
              let heightValue = reader.readBits(12),
              let aspectRatio = reader.readBits(4),
              let frameRateCode = reader.readBits(4)
        else { return nil }

        guard widthValue > 0, heightValue > 0 else { return nil }
        guard frameRateCode < UInt32(frameRateTable.count),
              let baseFrameRate = frameRateTable[Int(frameRateCode)]
        else { return nil }

        var width = Int(widthValue)
        var height = Int(heightValue)
        var frameRate = baseFrameRate
        var profileAndLevel: Int?
        var isProgressive = false
        var chromaFormat = 1

        // A sequence extension, when present, widens the size fields by two bits
        // each and scales the frame rate. Without it this is an MPEG-1 header.
        if let extensionStart = findSequenceExtension(bytes, from: headerStart + 4) {
            var extensionReader = BitstreamReader(bytes: Array(bytes[(extensionStart + 4)...]))
            // extension_start_code_identifier is 4 bits and must be 0001 for a
            // sequence extension.
            guard let identifier = extensionReader.readBits(4), identifier == 1 else {
                return SequenceHeader(
                    width: width,
                    height: height,
                    frameRate: frameRate,
                    aspectRatioInformation: Int(aspectRatio),
                    profileAndLevel: nil,
                    isProgressive: false,
                    chromaFormat: 1
                )
            }

            guard let profileLevel = extensionReader.readBits(8),
                  let progressive = extensionReader.readBit(),
                  let chroma = extensionReader.readBits(2),
                  let widthExtension = extensionReader.readBits(2),
                  let heightExtension = extensionReader.readBits(2),
                  extensionReader.skipBits(12),      // bit_rate_extension
                  extensionReader.readBit() != nil,  // marker_bit
                  extensionReader.skipBits(8),       // vbv_buffer_size_extension
                  extensionReader.readBit() != nil,  // low_delay
                  let frameRateExtensionN = extensionReader.readBits(2),
                  let frameRateExtensionD = extensionReader.readBits(5)
            else { return nil }

            width |= Int(widthExtension) << 12
            height |= Int(heightExtension) << 12
            profileAndLevel = Int(profileLevel)
            isProgressive = progressive
            chromaFormat = Int(chroma)
            frameRate = baseFrameRate
                * Double(frameRateExtensionN + 1)
                / Double(frameRateExtensionD + 1)
        }

        return SequenceHeader(
            width: width,
            height: height,
            frameRate: frameRate,
            aspectRatioInformation: Int(aspectRatio),
            profileAndLevel: profileAndLevel,
            isProgressive: isProgressive,
            chromaFormat: chromaFormat
        )
    }

    // MARK: - Frame Counting

    /// Counts coded pictures by scanning for picture start codes (0x00000100).
    ///
    /// Reference: ITU-T H.262 Table 6-1
    public static func countFrames(_ data: Data) -> Int {
        let bytes = [UInt8](data)
        guard bytes.count >= 4 else { return 0 }

        var count = 0
        var index = 0
        while index + 3 < bytes.count {
            if bytes[index] == 0x00, bytes[index + 1] == 0x00, bytes[index + 2] == 0x01,
               bytes[index + 3] == pictureStartCode {
                count += 1
                index += 4
                continue
            }
            index += 1
        }
        return count
    }

    // MARK: - Private

    /// Finds the next `00 00 01 <code>` start code at or after `from`.
    private static func findStartCode(_ bytes: [UInt8], code: UInt8, from: Int) -> Int? {
        guard bytes.count >= 4 else { return nil }
        var index = max(0, from)
        while index + 3 < bytes.count {
            if bytes[index] == 0x00, bytes[index + 1] == 0x00, bytes[index + 2] == 0x01,
               bytes[index + 3] == code {
                return index
            }
            index += 1
        }
        return nil
    }

    /// Finds the sequence extension that follows a sequence header.
    ///
    /// Only an extension appearing before the next sequence header or picture
    /// counts: a later extension belongs to a different structure.
    private static func findSequenceExtension(_ bytes: [UInt8], from: Int) -> Int? {
        var index = max(0, from)
        while index + 3 < bytes.count {
            if bytes[index] == 0x00, bytes[index + 1] == 0x00, bytes[index + 2] == 0x01 {
                let code = bytes[index + 3]
                if code == extensionStartCode { return index }
                // Any other start code means the sequence header ended without an
                // extension, which is an MPEG-1 stream.
                if code == pictureStartCode || code == groupStartCode
                    || code == sequenceHeaderCode {
                    return nil
                }
            }
            index += 1
        }
        return nil
    }
}

// MARK: - Stream Info

extension MPEG2Parser.SequenceHeader {
    /// Converts the parsed header into the codec-neutral summary.
    ///
    /// MPEG-2 codes no sample aspect ratio directly; `aspect_ratio_information`
    /// gives a *display* aspect ratio, from which square pixels are inferred when
    /// the coded size already matches that ratio.
    public var streamInfo: VideoStreamInfo {
        // Level identifiers map onto the level-times-ten convention used by the
        // other codecs only loosely, so the raw level is carried instead.
        let level = levelIdentifier ?? 0
        return VideoStreamInfo(
            codec: .mpeg2,
            width: width,
            height: height,
            profileIDC: profileIdentifier ?? 0,
            levelTimesTen: level,
            chromaFormat: ChromaFormat(rawValue: chromaFormat) ?? .yuv420,
            bitDepthLuma: 8,
            bitDepthChroma: 8,
            frameRate: frameRate,
            isProgressive: isProgressive,
            sampleAspectRatio: nil,
            mpeg2AspectRatioInformation: aspectRatioInformation
        )
    }
}
