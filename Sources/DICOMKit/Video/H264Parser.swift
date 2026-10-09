// NEMA-verified: 2026a, checked 2026-09-29 — carries no DICOM-standard data (ITU-T H.264 bitstream syntax, out of scope)
//
// H264Parser.swift
// DICOMKit
//
// Copyright © 2026 DICOMKit. All rights reserved.
//

import Foundation

/// Parses H.264/AVC Sequence Parameter Sets.
///
/// The SPS is what an H.264 stream says about its own geometry, profile and level.
/// Reading it is how the DICOM attributes are made to agree with the pixel data
/// rather than with whatever the caller believed.
///
/// Reference: ITU-T H.264 Section 7.3.2.1.1 (seq_parameter_set_data)
public enum H264Parser {

    // MARK: - NAL Unit Types

    /// NAL unit type for a Sequence Parameter Set.
    public static let spsNALType: UInt8 = 7
    /// NAL unit type for a Picture Parameter Set.
    public static let ppsNALType: UInt8 = 8
    /// NAL unit type for a coded slice of a non-IDR picture.
    public static let nonIDRSliceNALType: UInt8 = 1
    /// NAL unit type for a coded slice of an IDR picture.
    public static let idrSliceNALType: UInt8 = 5
    /// NAL unit type for Supplemental Enhancement Information.
    public static let seiNALType: UInt8 = 6
    /// NAL unit type for a subset Sequence Parameter Set, which describes the
    /// non-base views of an MVC (Stereo High / Multiview High) stream.
    public static let subsetSPSNALType: UInt8 = 15

    /// `profile_idc` of the Stereo High profile (ITU-T H.264 Annex H).
    public static let stereoHighProfileIDC = 128

    /// SEI `payloadType` of a frame packing arrangement (ITU-T H.264 D.1.26).
    static let framePackingArrangementPayloadType = 45

    /// The `profile_idc` values whose SPS carries the extended chroma / bit-depth
    /// block. Skipping this block for these profiles misreads every later field.
    ///
    /// Reference: ITU-T H.264 Section 7.3.2.1.1
    static let profilesWithChromaInfo: Set<UInt32> = [100, 110, 122, 244, 44, 83, 86, 118, 128, 138, 139, 134, 135]

    // MARK: - Sequence Parameter Set

    /// The fields of an H.264 SPS this toolkit needs.
    public struct SequenceParameterSet: Sendable, Hashable {
        public let profileIDC: Int
        public let levelIDC: Int
        public let constraintSetFlags: UInt8
        public let chromaFormatIDC: Int
        public let bitDepthLuma: Int
        public let bitDepthChroma: Int
        /// Width in luma samples, after subtracting the frame crop offsets.
        public let width: Int
        /// Height in luma samples, after subtracting the frame crop offsets.
        public let height: Int
        /// Coded width in luma samples: `PicWidthInMbs * 16`, before cropping.
        public let codedWidth: Int
        /// Coded frame height in luma samples: `FrameHeightInMbs * 16`, before
        /// cropping. For a field-coded stream this is the height of both fields.
        public let codedHeight: Int
        public let frameMBSOnly: Bool
        /// Frame rate from the VUI timing information, when present.
        public let frameRate: Double?
        /// Sample aspect ratio from the VUI, when present.
        public let sampleAspectRatio: (width: Int, height: Int)?

        public static func == (lhs: SequenceParameterSet, rhs: SequenceParameterSet) -> Bool {
            lhs.profileIDC == rhs.profileIDC
                && lhs.levelIDC == rhs.levelIDC
                && lhs.constraintSetFlags == rhs.constraintSetFlags
                && lhs.chromaFormatIDC == rhs.chromaFormatIDC
                && lhs.bitDepthLuma == rhs.bitDepthLuma
                && lhs.bitDepthChroma == rhs.bitDepthChroma
                && lhs.width == rhs.width
                && lhs.height == rhs.height
                && lhs.codedWidth == rhs.codedWidth
                && lhs.codedHeight == rhs.codedHeight
                && lhs.frameMBSOnly == rhs.frameMBSOnly
                && lhs.frameRate == rhs.frameRate
                && lhs.sampleAspectRatio?.width == rhs.sampleAspectRatio?.width
                && lhs.sampleAspectRatio?.height == rhs.sampleAspectRatio?.height
        }

        public func hash(into hasher: inout Hasher) {
            hasher.combine(profileIDC)
            hasher.combine(levelIDC)
            hasher.combine(width)
            hasher.combine(height)
            hasher.combine(bitDepthLuma)
        }
    }

    // MARK: - Parsing

    /// Parses an SPS from a NAL unit payload.
    ///
    /// - Parameter nalUnit: The NAL unit **including** its one-byte header, with
    ///   emulation prevention bytes still in place.
    /// - Returns: The parsed SPS, or nil if the unit is not an SPS or is malformed.
    public static func parseSPS(nalUnit: Data) -> SequenceParameterSet? {
        guard let first = nalUnit.first else { return nil }
        // forbidden_zero_bit(1) nal_ref_idc(2) nal_unit_type(5)
        guard first & 0x80 == 0 else { return nil }
        guard first & 0x1F == spsNALType else { return nil }
        return parseSPSPayload(nalUnit.dropFirst())
    }

    /// Parses an SPS from a payload that has had its NAL header removed.
    ///
    /// This is the form `avcC` stores parameter sets in, minus the header byte.
    public static func parseSPSPayload<C: DataProtocol>(_ payload: C) -> SequenceParameterSet? {
        let rbsp = NALUnit.removeEmulationPrevention(Data(payload))
        var reader = BitstreamReader(rbsp)

        guard let profileIDC = reader.readBits(8),
              let constraintFlags = reader.readBits(8),
              let levelIDC = reader.readBits(8),
              reader.readUE() != nil  // seq_parameter_set_id
        else { return nil }

        // The chroma / bit-depth block is present only for the profiles listed in
        // Section 7.3.2.1.1. Reading it unconditionally — or skipping it always —
        // desynchronizes every field that follows.
        var chromaFormatIDC: UInt32 = 1      // 4:2:0 when not coded
        var bitDepthLuma: UInt32 = 8
        var bitDepthChroma: UInt32 = 8

        if profilesWithChromaInfo.contains(profileIDC) {
            guard let chroma = reader.readUE() else { return nil }
            chromaFormatIDC = chroma

            if chroma == 3 {
                // separate_colour_plane_flag
                guard reader.readBit() != nil else { return nil }
            }

            guard let lumaMinus8 = reader.readUE(),
                  let chromaMinus8 = reader.readUE(),
                  reader.readBit() != nil  // qpprime_y_zero_transform_bypass_flag
            else { return nil }
            bitDepthLuma = lumaMinus8 + 8
            bitDepthChroma = chromaMinus8 + 8

            guard let scalingMatrixPresent = reader.readBit() else { return nil }
            if scalingMatrixPresent {
                let listCount = chroma != 3 ? 8 : 12
                for index in 0..<listCount {
                    guard let listPresent = reader.readBit() else { return nil }
                    if listPresent {
                        let size = index < 6 ? 16 : 64
                        guard skipScalingList(&reader, size: size) else { return nil }
                    }
                }
            }
        }

        guard reader.readUE() != nil,               // log2_max_frame_num_minus4
              let picOrderCntType = reader.readUE()
        else { return nil }

        if picOrderCntType == 0 {
            guard reader.readUE() != nil else { return nil }  // log2_max_pic_order_cnt_lsb_minus4
        } else if picOrderCntType == 1 {
            guard reader.readBit() != nil,          // delta_pic_order_always_zero_flag
                  reader.readSE() != nil,           // offset_for_non_ref_pic
                  reader.readSE() != nil,           // offset_for_top_to_bottom_field
                  let cycleLength = reader.readUE()
            else { return nil }
            // A malformed stream can claim an enormous cycle; cap it rather than
            // spinning through millions of reads.
            guard cycleLength <= 255 else { return nil }
            for _ in 0..<cycleLength {
                guard reader.readSE() != nil else { return nil }
            }
        }

        guard reader.readUE() != nil,               // max_num_ref_frames
              reader.readBit() != nil,              // gaps_in_frame_num_value_allowed_flag
              let picWidthInMBsMinus1 = reader.readUE(),
              let picHeightInMapUnitsMinus1 = reader.readUE(),
              let frameMBSOnlyFlag = reader.readBit()
        else { return nil }

        if !frameMBSOnlyFlag {
            guard reader.readBit() != nil else { return nil }  // mb_adaptive_frame_field_flag
        }

        guard reader.readBit() != nil else { return nil }      // direct_8x8_inference_flag

        // Frame cropping. Omitting this is the single most common bug in this
        // area: a 1920x1080 stream codes 68 macroblock rows (1088 luma samples)
        // and crops the extra 8, so skipping the offsets reports 1088, not 1080.
        guard let frameCroppingFlag = reader.readBit() else { return nil }
        var cropLeft: UInt32 = 0
        var cropRight: UInt32 = 0
        var cropTop: UInt32 = 0
        var cropBottom: UInt32 = 0
        if frameCroppingFlag {
            guard let left = reader.readUE(),
                  let right = reader.readUE(),
                  let top = reader.readUE(),
                  let bottom = reader.readUE()
            else { return nil }
            cropLeft = left
            cropRight = right
            cropTop = top
            cropBottom = bottom
        }

        // Crop offsets are in chroma-sample units for 4:2:0 and 4:2:2, and in luma
        // samples for monochrome and 4:4:4.
        let subWidthC: UInt32
        let subHeightC: UInt32
        switch chromaFormatIDC {
        case 0: subWidthC = 1; subHeightC = 1            // monochrome
        case 1: subWidthC = 2; subHeightC = 2            // 4:2:0
        case 2: subWidthC = 2; subHeightC = 1            // 4:2:2
        default: subWidthC = 1; subHeightC = 1           // 4:4:4
        }
        let cropUnitX = subWidthC
        let cropUnitY = subHeightC * (frameMBSOnlyFlag ? 1 : 2)

        let codedWidth = (UInt64(picWidthInMBsMinus1) + 1) * 16
        let codedHeight = (UInt64(picHeightInMapUnitsMinus1) + 1) * 16 * (frameMBSOnlyFlag ? 1 : 2)

        let horizontalCrop = UInt64(cropUnitX) * (UInt64(cropLeft) + UInt64(cropRight))
        let verticalCrop = UInt64(cropUnitY) * (UInt64(cropTop) + UInt64(cropBottom))
        guard codedWidth > horizontalCrop, codedHeight > verticalCrop else { return nil }

        let width = Int(codedWidth - horizontalCrop)
        let height = Int(codedHeight - verticalCrop)

        // VUI parameters: optional, and the only place a frame rate or a sample
        // aspect ratio is coded.
        var frameRate: Double?
        var sampleAspectRatio: (width: Int, height: Int)?
        if let vuiPresent = reader.readBit(), vuiPresent {
            let vui = parseVUI(&reader)
            frameRate = vui.frameRate
            sampleAspectRatio = vui.sampleAspectRatio
        }

        return SequenceParameterSet(
            profileIDC: Int(profileIDC),
            levelIDC: Int(levelIDC),
            constraintSetFlags: UInt8(truncatingIfNeeded: constraintFlags),
            chromaFormatIDC: Int(chromaFormatIDC),
            bitDepthLuma: Int(bitDepthLuma),
            bitDepthChroma: Int(bitDepthChroma),
            width: width,
            height: height,
            codedWidth: Int(codedWidth),
            codedHeight: Int(codedHeight),
            frameMBSOnly: frameMBSOnlyFlag,
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

    // MARK: - Subset Sequence Parameter Set

    /// Parses the `seq_parameter_set_data` that opens a subset SPS.
    ///
    /// An MVC stream's base view is described by an ordinary SPS - usually High
    /// profile, so that a 2D decoder can play it - and the dependent view by a
    /// subset SPS carrying the Stereo High or Multiview High `profile_idc`. Only
    /// the subset SPS reveals that the stream is stereo at all.
    ///
    /// - Parameter nalUnit: The NAL unit **including** its one-byte header.
    /// - Returns: The parsed fields, or nil if the unit is not a subset SPS.
    ///
    /// Reference: ITU-T H.264 Section 7.3.2.1.3 (subset_seq_parameter_set_rbsp)
    public static func parseSubsetSPS(nalUnit: Data) -> SequenceParameterSet? {
        guard let first = nalUnit.first else { return nil }
        guard first & 0x80 == 0, first & 0x1F == subsetSPSNALType else { return nil }
        return parseSPSPayload(nalUnit.dropFirst())
    }

    /// The first subset SPS among some NAL units, when there is one.
    public static func firstSubsetSPS(in nalUnits: [Data]) -> SequenceParameterSet? {
        for unit in nalUnits {
            if let sps = parseSubsetSPS(nalUnit: unit) { return sps }
        }
        return nil
    }

    // MARK: - Frame Packing

    /// Whether any of the NAL units is an SEI carrying an active frame packing
    /// arrangement - the signal that each picture packs two views for 3D.
    ///
    /// An arrangement with `frame_packing_arrangement_cancel_flag` set withdraws
    /// an earlier one, so it does not count.
    ///
    /// Reference: ITU-T H.264 Sections 7.3.2.3 (sei_rbsp) and D.1.26
    public static func containsFramePackingSEI(_ nalUnits: [Data]) -> Bool {
        nalUnits.contains { unit in
            guard let header = unit.first, header & 0x1F == seiNALType else { return false }
            let rbsp = [UInt8](NALUnit.removeEmulationPrevention(Data(unit.dropFirst())))
            return seiMessagesContainFramePacking(rbsp)
        }
    }

    /// Walks the `sei_message` list of one SEI RBSP.
    private static func seiMessagesContainFramePacking(_ rbsp: [UInt8]) -> Bool {
        var offset = 0
        // Each message needs at least a type byte and a size byte; anything
        // shorter is the rbsp_trailing_bits.
        while offset + 2 <= rbsp.count {
            var payloadType = 0
            while offset < rbsp.count, rbsp[offset] == 0xFF {
                payloadType += 255
                offset += 1
            }
            guard offset < rbsp.count else { return false }
            payloadType += Int(rbsp[offset])
            offset += 1

            var payloadSize = 0
            while offset < rbsp.count, rbsp[offset] == 0xFF {
                payloadSize += 255
                offset += 1
            }
            guard offset < rbsp.count else { return false }
            payloadSize += Int(rbsp[offset])
            offset += 1

            guard offset + payloadSize <= rbsp.count else { return false }
            if payloadType == framePackingArrangementPayloadType {
                var reader = BitstreamReader(bytes: Array(rbsp[offset..<(offset + payloadSize)]))
                // frame_packing_arrangement_id, then the cancel flag.
                if reader.readUE() != nil, let cancelled = reader.readBit(), !cancelled {
                    return true
                }
            }
            offset += payloadSize
            // rbsp_trailing_bits: a lone stop bit ends the message list.
            if offset < rbsp.count, rbsp[offset] == 0x80, offset == rbsp.count - 1 { return false }
        }
        return false
    }

    // MARK: - Access Unit Counting

    /// Counts coded pictures in an Annex B stream.
    ///
    /// A new picture starts at a VCL NAL unit (type 1 or 5) whose
    /// `first_mb_in_slice` is 0; later slices of the same picture carry a non-zero
    /// value. This is the fallback for raw elementary streams — a container's
    /// sample table gives an exact count far more cheaply.
    ///
    /// Reference: ITU-T H.264 Section 7.3.3
    public static func countFrames(annexB: Data) -> Int {
        var count = 0
        for unit in NALUnit.splitAnnexB(annexB) {
            guard let header = unit.first else { continue }
            let type = header & 0x1F
            guard type == nonIDRSliceNALType || type == idrSliceNALType else { continue }

            let rbsp = NALUnit.removeEmulationPrevention(Data(unit.dropFirst()))
            var reader = BitstreamReader(rbsp)
            guard let firstMBInSlice = reader.readUE() else { continue }
            if firstMBInSlice == 0 {
                count += 1
            }
        }
        return count
    }

    // MARK: - Private

    /// Consumes a scaling list without retaining it.
    private static func skipScalingList(_ reader: inout BitstreamReader, size: Int) -> Bool {
        var lastScale = 8
        var nextScale = 8
        for _ in 0..<size {
            if nextScale != 0 {
                guard let delta = reader.readSE() else { return false }
                nextScale = (lastScale + Int(delta) + 256) % 256
            }
            lastScale = nextScale == 0 ? lastScale : nextScale
        }
        return true
    }

    /// Parses the VUI fields this toolkit uses, tolerating a truncated block.
    ///
    /// Reference: ITU-T H.264 Annex E.1.1
    private static func parseVUI(
        _ reader: inout BitstreamReader
    ) -> (frameRate: Double?, sampleAspectRatio: (width: Int, height: Int)?) {
        var sampleAspectRatio: (width: Int, height: Int)?

        guard let aspectRatioInfoPresent = reader.readBit() else { return (nil, nil) }
        if aspectRatioInfoPresent {
            guard let idc = reader.readBits(8) else { return (nil, nil) }
            if idc == 255 {  // Extended_SAR
                guard let sarWidth = reader.readBits(16),
                      let sarHeight = reader.readBits(16)
                else { return (nil, nil) }
                sampleAspectRatio = (Int(sarWidth), Int(sarHeight))
            } else if let ratio = Self.aspectRatioTable[Int(idc)] {
                sampleAspectRatio = ratio
            }
        }

        guard let overscanPresent = reader.readBit() else { return (nil, sampleAspectRatio) }
        if overscanPresent {
            guard reader.readBit() != nil else { return (nil, sampleAspectRatio) }
        }

        guard let videoSignalTypePresent = reader.readBit() else { return (nil, sampleAspectRatio) }
        if videoSignalTypePresent {
            guard reader.skipBits(4) else { return (nil, sampleAspectRatio) }  // format(3) + full_range(1)
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

        guard let timingInfoPresent = reader.readBit() else { return (nil, sampleAspectRatio) }
        guard timingInfoPresent else { return (nil, sampleAspectRatio) }

        guard let numUnitsInTick = reader.readBits(32),
              let timeScale = reader.readBits(32),
              numUnitsInTick > 0
        else { return (nil, sampleAspectRatio) }

        // time_scale counts field ticks, so a frame takes two of them.
        let frameRate = Double(timeScale) / (2.0 * Double(numUnitsInTick))
        guard frameRate.isFinite, frameRate > 0, frameRate < 1000 else {
            return (nil, sampleAspectRatio)
        }
        return (frameRate, sampleAspectRatio)
    }

    /// `aspect_ratio_idc` to sample aspect ratio, per ITU-T H.264 Table E-1.
    private static let aspectRatioTable: [Int: (width: Int, height: Int)] = [
        1: (1, 1), 2: (12, 11), 3: (10, 11), 4: (16, 11), 5: (40, 33),
        6: (24, 11), 7: (20, 11), 8: (32, 11), 9: (80, 33), 10: (18, 11),
        11: (15, 11), 12: (64, 33), 13: (160, 99), 14: (4, 3), 15: (3, 2),
        16: (2, 1),
    ]
}

// MARK: - Stream Info

extension H264Parser.SequenceParameterSet {
    /// Converts the parsed SPS into the codec-neutral summary.
    public var streamInfo: VideoStreamInfo {
        return VideoStreamInfo(
            codec: .h264,
            width: width,
            height: height,
            profileIDC: profileIDC,
            levelTimesTen: levelIDC,
            chromaFormat: ChromaFormat(rawValue: chromaFormatIDC) ?? .yuv420,
            bitDepthLuma: bitDepthLuma,
            bitDepthChroma: bitDepthChroma,
            frameRate: frameRate,
            isProgressive: frameMBSOnly,
            sampleAspectRatio: sampleAspectRatio,
            codedWidth: codedWidth,
            codedHeight: codedHeight
        )
    }
}
