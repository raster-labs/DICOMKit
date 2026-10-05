// NEMA-verified: 2026a, checked 2026-09-30 — Cine Module Frame Time Vector (0018,1065) DS 1-n Type 1C, Preferred Playback Sequencing (0018,1244) US 1 Type 3 Enumerated Values 0/1, Image Trigger Delay (0018,1067) DS 1 Type 3, Effective Duration (0018,0072) DS 1 Type 3 per PS3.3 2026a Table C.7-13 and PS3.6 2026a Table 6-1 (verified by script); Frame Increment Pointer (0028,0009) per Table C.7-14 is implied by which of Frame Time / Frame Time Vector is present (D60)
// NEMA-verified: 2026a, checked 2026-09-30 — Channel Source (003A,0208) keeps any code: PS3.3 2026a Table C.7-13 includes Table 8.8-1 with "DCID 3000" and PS3.16 2026a CID 3000 Audio Channel Source is "Type: Extensible" (DCM 109110-109115 verified by script) (D57)
// NEMA-verified: 2026a, checked 2026-09-30 — transfer syntax detection via DICOMCore; UIDs per PS3.6 2026a Table A-1; Multiplexed Audio Channels Description Code Sequence (003A,0300) read per PS3.3 2026a Table C.7-13 (Channel Identification Code IS, Channel Mode CS MONO/STEREO, Channel Source Sequence with a PS3.16 CID 3000 code) (D46)
//
// VideoParser.swift
// DICOMKit
//
// Created by DICOMKit on 2026-02-09.
// Copyright © 2026 DICOMKit. All rights reserved.
//

import Foundation
import DICOMCore

/// Parser for DICOM Video objects
///
/// Parses Video IODs from DICOM data sets, extracting video metadata
/// and encapsulated pixel data.
///
/// Reference: PS3.3 A.32.5 - Video Endoscopic Image IOD
/// Reference: PS3.3 A.32.6 - Video Microscopic Image IOD
/// Reference: PS3.3 A.32.7 - Video Photographic Image IOD
public struct VideoParser {

    /// Parse a Video from a DICOM data set
    ///
    /// - Parameter dataSet: DICOM data set containing a Video IOD
    /// - Returns: Parsed Video
    /// - Throws: DICOMError if parsing fails
    public static func parse(from dataSet: DataSet) throws -> Video {
        // Parse SOP Instance UID (required)
        guard let sopInstanceUID = dataSet.string(for: .sopInstanceUID) else {
            throw DICOMError.parsingFailed("Missing SOP Instance UID")
        }

        let sopClassUID = dataSet.string(for: .sopClassUID) ?? Video.videoEndoscopicImageStorageUID

        // Parse Study and Series UIDs (required)
        guard let studyInstanceUID = dataSet.string(for: .studyInstanceUID) else {
            throw DICOMError.parsingFailed("Missing Study Instance UID")
        }

        guard let seriesInstanceUID = dataSet.string(for: .seriesInstanceUID) else {
            throw DICOMError.parsingFailed("Missing Series Instance UID")
        }

        // Parse Image Pixel Module (required)
        guard let rowsValue = dataSet[.rows]?.uint16Value else {
            throw DICOMError.parsingFailed("Missing Rows attribute")
        }

        guard let columnsValue = dataSet[.columns]?.uint16Value else {
            throw DICOMError.parsingFailed("Missing Columns attribute")
        }

        // Parse Number of Frames (required for video)
        let numberOfFrames: Int
        if let nfElement = dataSet[.numberOfFrames]?.integerStringValue {
            numberOfFrames = nfElement.value
        } else {
            throw DICOMError.parsingFailed("Missing Number of Frames attribute")
        }

        // Parse optional identification
        let instanceNumber = dataSet[.instanceNumber]?.integerStringValue?.value

        // Parse optional patient information
        let patientName = dataSet.string(for: .patientName)
        let patientID = dataSet.string(for: .patientID)

        // Parse optional series information
        let modality = dataSet.string(for: .modality)
        let seriesDescription = dataSet.string(for: .seriesDescription)
        let seriesNumber: Int?
        if let seriesNumElement = dataSet[.seriesNumber]?.integerStringValue {
            seriesNumber = seriesNumElement.value
        } else {
            seriesNumber = nil
        }

        // Parse Image Pixel Module attributes
        let samplesPerPixel = Int(dataSet[.samplesPerPixel]?.uint16Value ?? 3)
        let photometricInterpretation = dataSet.string(for: .photometricInterpretation)
            ?? Video.defaultPhotometricInterpretation
        let bitsAllocated = Int(dataSet[.bitsAllocated]?.uint16Value ?? 8)
        let bitsStored = Int(dataSet[.bitsStored]?.uint16Value ?? 8)
        let highBit = Int(dataSet[.highBit]?.uint16Value ?? 7)
        let pixelRepresentation = Int(dataSet[.pixelRepresentation]?.uint16Value ?? 0)
        let planarConfiguration: Int?
        if let pc = dataSet[.planarConfiguration]?.uint16Value {
            planarConfiguration = Int(pc)
        } else {
            planarConfiguration = nil
        }

        // Parse Cine Module attributes
        let frameTime = dataSet[.frameTime]?.decimalStringValue?.value
        let cineRate = dataSet[.cineRate]?.integerStringValue?.value
        let recommendedDisplayFrameRate = dataSet[.recommendedDisplayFrameRate]?.integerStringValue?.value
        let frameDelay = dataSet[.frameDelay]?.decimalStringValue?.value
        let actualFrameDuration = dataSet[.actualFrameDuration]?.integerStringValue?.value
        // Frame Time Vector (0018,1065) DS 1-n, Preferred Playback Sequencing
        // (0018,1244) US 1 (Enumerated Values 0 Looping, 1 Sweeping), Image Trigger
        // Delay (0018,1067) DS 1, Effective Duration (0018,0072) DS 1 — PS3.3 2026a
        // Table C.7-13, VR/VM per PS3.6 2026a Table 6-1. Values outside the
        // Enumerated Values are kept as read, not dropped, so a rewrite is faithful.
        let frameTimeVector = dataSet[.frameTimeVector]?.decimalStringValues?.map(\.value)
        let preferredPlaybackSequencing = dataSet[.preferredPlaybackSequencing]?.uint16Value.map(Int.init)
        let imageTriggerDelay = dataSet[Video.imageTriggerDelayTag]?.decimalStringValue?.value
        let effectiveDuration = dataSet[Video.effectiveDurationTag]?.decimalStringValue?.value

        // Parse trim points
        let startTrim = dataSet[.startTrim]?.integerStringValue?.value
        let stopTrim = dataSet[.stopTrim]?.integerStringValue?.value

        // Parse content date/time
        let contentDate = dataSet.date(for: .contentDate)
        let contentTime = dataSet.time(for: .contentTime)

        // Parse compression information
        let lossyImageCompression = dataSet.string(for: .lossyImageCompression)
        let lossyImageCompressionRatio = dataSet[.lossyImageCompressionRatio]?.decimalStringValue?.value
        let lossyImageCompressionMethod = dataSet.string(for: .lossyImageCompressionMethod)

        // Parse pixel data.
        //
        // Every video transfer syntax is encapsulated (PS3.5 A.4), so a conformant
        // file carries the bit stream in fragments and leaves `valueData` empty.
        // Fragments are concatenated in order: for the non-fragmentable UIDs there
        // is exactly one, and for the "….1" fragmentable variants the bit stream is
        // the concatenation of them all. The `valueData` branch is a fallback for
        // legacy files that (incorrectly) stored the stream as a native OB value.
        let pixelData: Data?
        var fragmentCount = 0
        if let pixelElement = dataSet[.pixelData] {
            if let fragments = pixelElement.encapsulatedFragments, !fragments.isEmpty {
                fragmentCount = fragments.count
                var combined = Data()
                for fragment in fragments {
                    combined.append(fragment)
                }
                pixelData = combined
            } else if !pixelElement.valueData.isEmpty {
                pixelData = pixelElement.valueData
            } else {
                pixelData = nil
            }
        } else {
            pixelData = nil
        }

        // Parse VL Image / General Equipment / General Acquisition / General Image
        // and the Type 2 study and patient identifiers. Zero-length Type 2 values
        // read back as empty strings; normalize those to nil so a round trip does
        // not turn "absent" into "present and empty" at the model level.
        let imageType = dataSet[.imageType]?.stringValues?.filter { !$0.isEmpty }
        let manufacturer = Self.nonEmpty(dataSet.string(for: .manufacturer))
        let manufacturerModelName = Self.nonEmpty(dataSet.string(for: .manufacturerModelName))
        let deviceSerialNumber = Self.nonEmpty(dataSet.string(for: .deviceSerialNumber))
        let softwareVersions = Self.nonEmpty(dataSet.string(for: .softwareVersions))
        let institutionName = Self.nonEmpty(dataSet.string(for: .institutionName))
        let acquisitionDate = dataSet.date(for: .acquisitionDate)
        let acquisitionTime = dataSet.time(for: .acquisitionTime)
        let patientOrientation = Self.nonEmpty(dataSet.string(for: .patientOrientation))
        let studyDate = dataSet.date(for: .studyDate)
        let studyTime = dataSet.time(for: .studyTime)
        let referringPhysicianName = Self.nonEmpty(dataSet.string(for: .referringPhysicianName))
        let studyID = Self.nonEmpty(dataSet.string(for: .studyID))
        let accessionNumber = Self.nonEmpty(dataSet.string(for: .accessionNumber))
        let patientBirthDate = dataSet.date(for: .patientBirthDate)
        let patientSex = Self.nonEmpty(dataSet.string(for: .patientSex))

        // Cine Module: Multiplexed Audio Channels Description Code Sequence
        // (003A,0300), Type 2C (PS3.3 Table C.7-13).
        let audioSequence = dataSet[VideoAudioChannel.multiplexedAudioChannelsDescriptionCodeSequence]
        let multiplexedAudioChannels = (audioSequence?.sequenceItems ?? [])
            .compactMap(Self.audioChannel)

        var video = Video(
            sopInstanceUID: sopInstanceUID,
            sopClassUID: sopClassUID,
            studyInstanceUID: studyInstanceUID,
            seriesInstanceUID: seriesInstanceUID,
            instanceNumber: instanceNumber,
            patientName: patientName,
            patientID: patientID,
            modality: modality,
            seriesDescription: seriesDescription,
            seriesNumber: seriesNumber,
            rows: Int(rowsValue),
            columns: Int(columnsValue),
            numberOfFrames: numberOfFrames,
            samplesPerPixel: samplesPerPixel,
            photometricInterpretation: photometricInterpretation,
            bitsAllocated: bitsAllocated,
            bitsStored: bitsStored,
            highBit: highBit,
            pixelRepresentation: pixelRepresentation,
            planarConfiguration: planarConfiguration,
            frameTime: frameTime,
            cineRate: cineRate,
            recommendedDisplayFrameRate: recommendedDisplayFrameRate,
            frameDelay: frameDelay,
            actualFrameDuration: actualFrameDuration,
            startTrim: startTrim,
            stopTrim: stopTrim,
            frameTimeVector: frameTimeVector.flatMap { $0.isEmpty ? nil : $0 },
            preferredPlaybackSequencing: preferredPlaybackSequencing,
            imageTriggerDelay: imageTriggerDelay,
            effectiveDuration: effectiveDuration,
            multiplexedAudioChannels: multiplexedAudioChannels,
            contentDate: contentDate,
            contentTime: contentTime,
            lossyImageCompression: lossyImageCompression,
            lossyImageCompressionRatio: lossyImageCompressionRatio,
            lossyImageCompressionMethod: lossyImageCompressionMethod,
            imageType: imageType ?? Video.defaultImageType,
            manufacturer: manufacturer,
            manufacturerModelName: manufacturerModelName,
            deviceSerialNumber: deviceSerialNumber,
            softwareVersions: softwareVersions,
            institutionName: institutionName,
            acquisitionDate: acquisitionDate,
            acquisitionTime: acquisitionTime,
            patientOrientation: patientOrientation,
            studyDate: studyDate,
            studyTime: studyTime,
            referringPhysicianName: referringPhysicianName,
            studyID: studyID,
            accessionNumber: accessionNumber,
            patientBirthDate: patientBirthDate,
            patientSex: patientSex,
            pixelData: pixelData,
            // Stereo Pairs Present (PS3.5 Table 8-8) and the fragmentation the
            // object already uses survive a parse-and-rewrite round trip.
            stereoPairsPresent: dataSet.string(for: .stereoPairsPresent) == "YES" ? true : nil,
            allowsMultipleFragments: fragmentCount > 1
        )
        // The sequence may be present with no Items, or with Items this model
        // cannot hold; keeping the flag writes it back rather than dropping it.
        video.containsUndescribedMultiplexedAudio = audioSequence != nil
        return video
    }

    /// One Item of (003A,0300), or nil when it lacks a Type 1 attribute or uses a
    /// value ``VideoAudioChannel`` cannot represent: a Channel Mode other than the
    /// Enumerated Values MONO and STEREO, or a Channel Source Item with no code.
    ///
    /// Any code is kept, not only CID 3000's: PS3.3 2026a Table C.7-13 includes
    /// the Code Sequence Macro with "DCID 3000", and PS3.16 2026a CID 3000 is
    /// "Type: Extensible" (D57).
    private static func audioChannel(_ item: SequenceItem) -> VideoAudioChannel? {
        guard let code = item[VideoAudioChannel.channelIdentificationCodeTag]?
                .integerStringValue?.value,
              let modeText = item.string(for: VideoAudioChannel.channelModeTag)?
                .trimmingCharacters(in: .whitespaces),
              let mode = VideoAudioChannel.Mode(rawValue: modeText),
              let sourceItem = item[.channelSourceSequence]?.sequenceItems?.first,
              let source = channelSource(sourceItem)
        else { return nil }
        return VideoAudioChannel(channelIdentificationCode: code, mode: mode, source: source)
    }

    /// The code of a Channel Source Sequence Item (PS3.3 Table 8.8-1): Code Value,
    /// Long Code Value or URN Code Value. Coding Scheme Designator is Type 1C,
    /// required with Code Value or Long Code Value; a URN code may omit it.
    private static func channelSource(_ item: SequenceItem) -> VideoAudioChannel.Source? {
        func text(_ tag: Tag) -> String? {
            nonEmpty(item.string(for: tag)?.trimmingCharacters(in: .whitespaces))
        }
        let short = text(.codeValue), long = text(.longCodeValue), urn = text(.urnCodeValue)
        let designator = text(.codingSchemeDesignator)
        guard let value = short ?? long ?? urn else { return nil }
        if short != nil || long != nil, designator == nil { return nil }
        return VideoAudioChannel.Source(CodedConcept(
            codeValue: value,
            codingSchemeDesignator: designator ?? "",
            codeMeaning: item.string(for: .codeMeaning)?.trimmingCharacters(in: .whitespaces) ?? "",
            codingSchemeVersion: text(.codingSchemeVersion),
            longCodeValue: short == nil ? long : nil,
            urnCodeValue: short == nil && long == nil ? urn : nil))
    }

    /// Maps an empty or whitespace-only string to nil.
    ///
    /// Type 2 attributes are written zero-length when unknown; reading one back as
    /// `""` would misrepresent "not supplied" as "supplied as empty".
    private static func nonEmpty(_ value: String?) -> String? {
        guard let value = value, !value.trimmingCharacters(in: .whitespaces).isEmpty else {
            return nil
        }
        return value
    }
}
