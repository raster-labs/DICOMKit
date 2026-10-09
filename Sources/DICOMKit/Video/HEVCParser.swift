// NEMA-verified: 2026a, checked 2026-09-29 — carries no DICOM-standard data (ITU-T H.265 bitstream syntax, out of scope)
//
// HEVCParser.swift
// DICOMKit
//
// Copyright © 2026 DICOMKit. All rights reserved.
//

import Foundation

/// Parses HEVC/H.265 Sequence Parameter Sets.
///
/// HEVC codes its geometry directly in luma samples rather than macroblocks, but
/// carries the same trap as H.264: a conformance window that must be subtracted
/// from the coded size to get the display size.
///
/// Reference: ITU-T H.265 Section 7.3.2.2.1 (seq_parameter_set_rbsp)
public enum HEVCParser {

    // MARK: - NAL Unit Types

    /// NAL unit type for a Video Parameter Set.
    public static let vpsNALType: UInt8 = 32
    /// NAL unit type for a Sequence Parameter Set.
    public static let spsNALType: UInt8 = 33
    /// NAL unit type for a Picture Parameter Set.
    public static let ppsNALType: UInt8 = 34

    /// The highest VCL NAL unit type. Types 0...31 are coded slice segments.
    public static let maxVCLNALType: UInt8 = 31

    // MARK: - Sequence Parameter Set

    /// The fields of an HEVC SPS this toolkit needs.
    public struct SequenceParameterSet: Sendable, Hashable {
        /// `general_profile_idc`: 1 is Main, 2 is Main 10.
        public let profileIDC: Int
        /// `general_level_idc` normalized to level-times-ten, so level 5.1 is 51.
        public let levelTimesTen: Int
        /// `general_tier_flag`: false is Main tier, true is High tier.
        public let isHighTier: Bool
        public let chromaFormatIDC: Int
        /// Width in luma samples, after subtracting the conformance window.
        public let width: Int
        /// Height in luma samples, after subtracting the conformance window.
        public let height: Int
        /// `pic_width_in_luma_samples`: the coded width, before the window.
        public let codedWidth: Int
        /// `pic_height_in_luma_samples`: the coded height, before the window.
        public let codedHeight: Int
        public let bitDepthLuma: Int
        public let bitDepthChroma: Int
        /// Frame rate from the VUI timing information, when present.
        public let frameRate: Double?
        /// Sample aspect ratio from the VUI, when present.
        public let sampleAspectRatio: (width: Int, height: Int)?

        public static func == (lhs: SequenceParameterSet, rhs: SequenceParameterSet) -> Bool {
            lhs.profileIDC == rhs.profileIDC
                && lhs.levelTimesTen == rhs.levelTimesTen
                && lhs.isHighTier == rhs.isHighTier
                && lhs.chromaFormatIDC == rhs.chromaFormatIDC
                && lhs.width == rhs.width
                && lhs.height == rhs.height
                && lhs.codedWidth == rhs.codedWidth
                && lhs.codedHeight == rhs.codedHeight
                && lhs.bitDepthLuma == rhs.bitDepthLuma
                && lhs.bitDepthChroma == rhs.bitDepthChroma
                && lhs.frameRate == rhs.frameRate
                && lhs.sampleAspectRatio?.width == rhs.sampleAspectRatio?.width
                && lhs.sampleAspectRatio?.height == rhs.sampleAspectRatio?.height
        }

        public func hash(into hasher: inout Hasher) {
            hasher.combine(profileIDC)
            hasher.combine(levelTimesTen)
            hasher.combine(width)
            hasher.combine(height)
            hasher.combine(bitDepthLuma)
        }
    }

    // MARK: - Parsing

    /// Parses an SPS from a NAL unit payload.
    ///
    /// - Parameter nalUnit: The NAL unit **including** its two-byte header, with
    ///   emulation prevention bytes still in place.
    public static func parseSPS(nalUnit: Data) -> SequenceParameterSet? {
        guard nalUnit.count >= 3 else { return nil }
        let bytes = [UInt8](nalUnit)
        // forbidden_zero_bit(1) nal_unit_type(6) nuh_layer_id(6) nuh_temporal_id_plus1(3)
        guard bytes[0] & 0x80 == 0 else { return nil }
        let type = (bytes[0] >> 1) & 0x3F
        guard type == spsNALType else { return nil }
        return parseSPSPayload(nalUnit.dropFirst(2))
    }

    /// Parses an SPS from a payload that has had its two-byte NAL header removed.
    ///
    /// This is the form `hvcC` stores parameter sets in, minus the header.
    public static func parseSPSPayload<C: DataProtocol>(_ payload: C) -> SequenceParameterSet? {
        let rbsp = NALUnit.removeEmulationPrevention(Data(payload))
        var reader = BitstreamReader(rbsp)

        guard reader.skipBits(4),                          // sps_video_parameter_set_id
              let maxSubLayersMinus1 = reader.readBits(3),
              reader.readBit() != nil                      // sps_temporal_id_nesting_flag
        else { return nil }

        guard let ptl = parseProfileTierLevel(&reader, maxSubLayersMinus1: Int(maxSubLayersMinus1))
        else { return nil }

        guard reader.readUE() != nil,                      // sps_seq_parameter_set_id
              let chromaFormatIDC = reader.readUE()
        else { return nil }

        if chromaFormatIDC == 3 {
            guard reader.readBit() != nil else { return nil }  // separate_colour_plane_flag
        }

        guard let picWidth = reader.readUE(),
              let picHeight = reader.readUE(),
              let conformanceWindowFlag = reader.readBit()
        else { return nil }

        // The conformance window is HEVC's equivalent of H.264 frame cropping, and
        // carries the same trap: omitting it reports the coded size, not the
        // display size.
        var winLeft: UInt32 = 0
        var winRight: UInt32 = 0
        var winTop: UInt32 = 0
        var winBottom: UInt32 = 0
        if conformanceWindowFlag {
            guard let left = reader.readUE(),
                  let right = reader.readUE(),
                  let top = reader.readUE(),
                  let bottom = reader.readUE()
            else { return nil }
            winLeft = left
            winRight = right
            winTop = top
            winBottom = bottom
        }

        guard let bitDepthLumaMinus8 = reader.readUE(),
              let bitDepthChromaMinus8 = reader.readUE()
        else { return nil }

        // Window offsets are in chroma sample units.
        let subWidthC: UInt32 = (chromaFormatIDC == 1 || chromaFormatIDC == 2) ? 2 : 1
        let subHeightC: UInt32 = (chromaFormatIDC == 1) ? 2 : 1

        let horizontalCrop = UInt64(subWidthC) * (UInt64(winLeft) + UInt64(winRight))
        let verticalCrop = UInt64(subHeightC) * (UInt64(winTop) + UInt64(winBottom))
        guard UInt64(picWidth) > horizontalCrop, UInt64(picHeight) > verticalCrop else {
            return nil
        }

        let width = Int(UInt64(picWidth) - horizontalCrop)
        let height = Int(UInt64(picHeight) - verticalCrop)

        // Walk to the VUI. The intervening fields are variable-length, so this
        // decodes them rather than guessing an offset.
        var frameRate: Double?
        var sampleAspectRatio: (width: Int, height: Int)?
        if let vui = parseTrailingVUI(&reader, maxSubLayersMinus1: Int(maxSubLayersMinus1)) {
            frameRate = vui.frameRate
            sampleAspectRatio = vui.sampleAspectRatio
        }

        return SequenceParameterSet(
            profileIDC: ptl.profileIDC,
            levelTimesTen: ptl.levelTimesTen,
            isHighTier: ptl.isHighTier,
            chromaFormatIDC: Int(chromaFormatIDC),
            width: width,
            height: height,
            codedWidth: Int(picWidth),
            codedHeight: Int(picHeight),
            bitDepthLuma: Int(bitDepthLumaMinus8) + 8,
            bitDepthChroma: Int(bitDepthChromaMinus8) + 8,
            frameRate: frameRate,
            sampleAspectRatio: sampleAspectRatio
        )
    }

    /// Finds and parses the first SPS in an Annex B byte stream.
    public static func parseFirstSPS(annexB: Data) -> SequenceParameterSet? {
        for unit in NALUnit.splitAnnexB(annexB) {
            if let sps = parseSPS(nalUnit: unit) {
                return sps
            }
        }
        return nil
    }

    // MARK: - Access Unit Counting

    /// Counts coded pictures in an Annex B stream.
    ///
    /// A new picture starts at a VCL NAL unit (types 0...31) whose
    /// `first_slice_segment_in_pic_flag` is 1.
    ///
    /// Reference: ITU-T H.265 Section 7.3.6.1
    public static func countFrames(annexB: Data) -> Int {
        var count = 0
        for unit in NALUnit.splitAnnexB(annexB) {
            guard unit.count >= 3 else { continue }
            let bytes = [UInt8](unit)
            let type = (bytes[0] >> 1) & 0x3F
            guard type <= maxVCLNALType else { continue }

            let rbsp = NALUnit.removeEmulationPrevention(Data(unit.dropFirst(2)))
            var reader = BitstreamReader(rbsp)
            guard let firstSliceInPic = reader.readBit() else { continue }
            if firstSliceInPic {
                count += 1
            }
        }
        return count
    }

    // MARK: - Private

    private struct ProfileTierLevel {
        let profileIDC: Int
        let levelTimesTen: Int
        let isHighTier: Bool
    }

    /// Parses `profile_tier_level`, whose length depends on the sub-layer count.
    ///
    /// Reference: ITU-T H.265 Section 7.3.3
    private static func parseProfileTierLevel(
        _ reader: inout BitstreamReader,
        maxSubLayersMinus1: Int
    ) -> ProfileTierLevel? {
        guard reader.skipBits(2) else { return nil }            // general_profile_space
        guard let tierFlag = reader.readBit() else { return nil }
        guard let profileIDC = reader.readBits(5) else { return nil }

        // general_profile_compatibility_flag[32] + the 48-bit constraint block
        // (progressive_source, interlaced_source, non_packed_constraint,
        // frame_only_constraint, and 44 reserved bits).
        guard reader.skipBits(32), reader.skipBits(48) else { return nil }

        guard let generalLevelIDC = reader.readBits(8) else { return nil }

        // Sub-layer profile/level presence flags, then their payloads.
        var subLayerProfilePresent = [Bool]()
        var subLayerLevelPresent = [Bool]()
        for _ in 0..<maxSubLayersMinus1 {
            guard let profilePresent = reader.readBit(),
                  let levelPresent = reader.readBit()
            else { return nil }
            subLayerProfilePresent.append(profilePresent)
            subLayerLevelPresent.append(levelPresent)
        }

        if maxSubLayersMinus1 > 0 {
            // reserved_zero_2bits, padded out to 8 entries.
            for _ in maxSubLayersMinus1..<8 {
                guard reader.skipBits(2) else { return nil }
            }
        }

        for index in 0..<maxSubLayersMinus1 {
            if subLayerProfilePresent[index] {
                guard reader.skipBits(88) else { return nil }   // 2+1+5+32+48
            }
            if subLayerLevelPresent[index] {
                guard reader.skipBits(8) else { return nil }
            }
        }

        // general_level_idc is level times 30, so 5.1 codes as 153. Normalize to
        // level-times-ten, which is how H.264 codes it and how callers compare.
        let levelTimesTen = Int((Double(generalLevelIDC) / 30.0 * 10.0).rounded())

        return ProfileTierLevel(
            profileIDC: Int(profileIDC),
            levelTimesTen: levelTimesTen,
            isHighTier: tierFlag
        )
    }

    /// Decodes the SPS fields between the bit depths and the VUI, then the VUI.
    ///
    /// Returns nil rather than failing the whole parse when the trailing fields
    /// cannot be walked: a frame rate is useful but not essential, and geometry
    /// has already been recovered by this point.
    ///
    /// Reference: ITU-T H.265 Sections 7.3.2.2.1 and E.2.1
    private static func parseTrailingVUI(
        _ reader: inout BitstreamReader,
        maxSubLayersMinus1: Int
    ) -> (frameRate: Double?, sampleAspectRatio: (width: Int, height: Int)?)? {
        guard reader.readUE() != nil,                    // log2_max_pic_order_cnt_lsb_minus4
              let subLayerOrderingInfoPresent = reader.readBit()
        else { return nil }

        let start = subLayerOrderingInfoPresent ? 0 : maxSubLayersMinus1
        for _ in start...maxSubLayersMinus1 {
            guard reader.readUE() != nil,                // sps_max_dec_pic_buffering_minus1
                  reader.readUE() != nil,                // sps_max_num_reorder_pics
                  reader.readUE() != nil                 // sps_max_latency_increase_plus1
            else { return nil }
        }

        guard reader.readUE() != nil,   // log2_min_luma_coding_block_size_minus3
              reader.readUE() != nil,   // log2_diff_max_min_luma_coding_block_size
              reader.readUE() != nil,   // log2_min_luma_transform_block_size_minus2
              reader.readUE() != nil,   // log2_diff_max_min_luma_transform_block_size
              reader.readUE() != nil,   // max_transform_hierarchy_depth_inter
              reader.readUE() != nil,   // max_transform_hierarchy_depth_intra
              let scalingListEnabled = reader.readBit()
        else { return nil }

        if scalingListEnabled {
            guard let scalingListDataPresent = reader.readBit() else { return nil }
            if scalingListDataPresent {
                guard skipScalingListData(&reader) else { return nil }
            }
        }

        guard reader.readBit() != nil,                   // amp_enabled_flag
              reader.readBit() != nil,                   // sample_adaptive_offset_enabled_flag
              let pcmEnabled = reader.readBit()
        else { return nil }

        if pcmEnabled {
            guard reader.skipBits(8),                    // pcm bit depths
                  reader.readUE() != nil,                // log2_min_pcm_luma_coding_block_size_minus3
                  reader.readUE() != nil,                // log2_diff_max_min_pcm_luma_coding_block_size
                  reader.readBit() != nil                // pcm_loop_filter_disabled_flag
            else { return nil }
        }

        guard let numShortTermRefPicSets = reader.readUE() else { return nil }
        guard numShortTermRefPicSets <= 64 else { return nil }
        // Short-term reference picture sets are inter-predictable and awkward to
        // walk; when any are present, stop rather than risk desynchronizing.
        // Geometry and profile are already recovered, so only the frame rate is
        // lost, and a container's declared rate covers that.
        if numShortTermRefPicSets > 0 { return (nil, nil) }

        guard let longTermRefPicsPresent = reader.readBit() else { return nil }
        if longTermRefPicsPresent {
            guard let numLongTerm = reader.readUE(), numLongTerm <= 32 else { return nil }
            if numLongTerm > 0 { return (nil, nil) }
        }

        guard reader.readBit() != nil,                   // sps_temporal_mvp_enabled_flag
              reader.readBit() != nil,                   // strong_intra_smoothing_enabled_flag
              let vuiPresent = reader.readBit()
        else { return nil }

        guard vuiPresent else { return (nil, nil) }
        return parseVUI(&reader, maxSubLayersMinus1: maxSubLayersMinus1)
    }

    /// Parses the VUI fields this toolkit uses.
    ///
    /// Reference: ITU-T H.265 Annex E.2.1
    private static func parseVUI(
        _ reader: inout BitstreamReader,
        maxSubLayersMinus1: Int
    ) -> (frameRate: Double?, sampleAspectRatio: (width: Int, height: Int)?) {
        var sampleAspectRatio: (width: Int, height: Int)?

        guard let aspectRatioInfoPresent = reader.readBit() else { return (nil, nil) }
        if aspectRatioInfoPresent {
            guard let idc = reader.readBits(8) else { return (nil, nil) }
            if idc == 255 {
                guard let sarWidth = reader.readBits(16),
                      let sarHeight = reader.readBits(16)
                else { return (nil, nil) }
                sampleAspectRatio = (Int(sarWidth), Int(sarHeight))
            } else if let ratio = aspectRatioTable[Int(idc)] {
                sampleAspectRatio = ratio
            }
        }

        guard let overscanPresent = reader.readBit() else { return (nil, sampleAspectRatio) }
        if overscanPresent {
            guard reader.readBit() != nil else { return (nil, sampleAspectRatio) }
        }

        guard let videoSignalTypePresent = reader.readBit() else { return (nil, sampleAspectRatio) }
        if videoSignalTypePresent {
            guard reader.skipBits(4) else { return (nil, sampleAspectRatio) }
            guard let colourDescriptionPresent = reader.readBit() else { return (nil, sampleAspectRatio) }
            if colourDescriptionPresent {
                guard reader.skipBits(24) else { return (nil, sampleAspectRatio) }
            }
        }

        guard let chromaLocPresent = reader.readBit() else { return (nil, sampleAspectRatio) }
        if chromaLocPresent {
            guard reader.readUE() != nil, reader.readUE() != nil else {
                return (nil, sampleAspectRatio)
            }
        }

        guard reader.readBit() != nil,       // neutral_chroma_indication_flag
              reader.readBit() != nil,       // field_seq_flag
              reader.readBit() != nil,       // frame_field_info_present_flag
              let defaultDisplayWindow = reader.readBit()
        else { return (nil, sampleAspectRatio) }

        if defaultDisplayWindow {
            guard reader.readUE() != nil, reader.readUE() != nil,
                  reader.readUE() != nil, reader.readUE() != nil
            else { return (nil, sampleAspectRatio) }
        }

        guard let timingInfoPresent = reader.readBit() else { return (nil, sampleAspectRatio) }
        guard timingInfoPresent else { return (nil, sampleAspectRatio) }

        guard let numUnitsInTick = reader.readBits(32),
              let timeScale = reader.readBits(32),
              numUnitsInTick > 0
        else { return (nil, sampleAspectRatio) }

        // Unlike H.264, HEVC's time_scale counts frame ticks directly.
        let frameRate = Double(timeScale) / Double(numUnitsInTick)
        guard frameRate.isFinite, frameRate > 0, frameRate < 1000 else {
            return (nil, sampleAspectRatio)
        }
        return (frameRate, sampleAspectRatio)
    }

    /// Consumes `scaling_list_data` without retaining it.
    ///
    /// Reference: ITU-T H.265 Section 7.3.4
    private static func skipScalingListData(_ reader: inout BitstreamReader) -> Bool {
        for sizeID in 0..<4 {
            var matrixID = 0
            let step = (sizeID == 3) ? 3 : 1
            while matrixID < 6 {
                guard let predModeFlag = reader.readBit() else { return false }
                if !predModeFlag {
                    guard reader.readUE() != nil else { return false }  // pred_matrix_id_delta
                } else {
                    let coefficients = min(64, 1 << (4 + (sizeID << 1)))
                    if sizeID > 1 {
                        guard reader.readSE() != nil else { return false }  // dc_coef
                    }
                    for _ in 0..<coefficients {
                        guard reader.readSE() != nil else { return false }
                    }
                }
                matrixID += step
            }
        }
        return true
    }

    /// `aspect_ratio_idc` to sample aspect ratio, per ITU-T H.265 Table E-1.
    private static let aspectRatioTable: [Int: (width: Int, height: Int)] = [
        1: (1, 1), 2: (12, 11), 3: (10, 11), 4: (16, 11), 5: (40, 33),
        6: (24, 11), 7: (20, 11), 8: (32, 11), 9: (80, 33), 10: (18, 11),
        11: (15, 11), 12: (64, 33), 13: (160, 99), 14: (4, 3), 15: (3, 2),
        16: (2, 1),
    ]
}

// MARK: - Stream Info

extension HEVCParser.SequenceParameterSet {
    /// Converts the parsed SPS into the codec-neutral summary.
    public var streamInfo: VideoStreamInfo {
        return VideoStreamInfo(
            codec: .h265,
            width: width,
            height: height,
            profileIDC: profileIDC,
            levelTimesTen: levelTimesTen,
            chromaFormat: ChromaFormat(rawValue: chromaFormatIDC) ?? .yuv420,
            bitDepthLuma: bitDepthLuma,
            bitDepthChroma: bitDepthChroma,
            frameRate: frameRate,
            isProgressive: true,
            sampleAspectRatio: sampleAspectRatio,
            codedWidth: codedWidth,
            codedHeight: codedHeight,
            isHighTier: isHighTier
        )
    }
}
