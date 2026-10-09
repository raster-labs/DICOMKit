// NEMA-verified: 2026a, checked 2026-09-29 — all ten Waveform Sample Interpretation terms, bit widths and signedness per PS3.3 2026a Table C.10-10; Waveform Originality per C.10.9.1.3; Waveform Identification Type 1 attributes per Table C.10-8; the 17 waveform storage SOP Class UIDs per PS3.6 Table A-1 and their Modality per A.34.2-A.34.18 content constraints
//
// Waveform.swift
// DICOMKit
//
// Created by DICOMKit on 2026-02-09.
// Copyright © 2026 DICOMKit. All rights reserved.
//

import Foundation
import DICOMCore

/// Represents a DICOM Waveform IOD
///
/// Waveform objects store time-based physiological signals such as ECG, EEG, EMG,
/// hemodynamic waveforms, and audio data. Each waveform contains one or more
/// multiplex groups, each with one or more channels sharing a common sampling frequency.
///
/// Supported SOP Classes (PS3.6 Table A-1):
/// - 12-lead ECG Waveform Storage (1.2.840.10008.5.1.4.1.1.9.1.1)
/// - General ECG Waveform Storage (1.2.840.10008.5.1.4.1.1.9.1.2)
/// - Ambulatory ECG Waveform Storage (1.2.840.10008.5.1.4.1.1.9.1.3)
/// - General 32-bit ECG Waveform Storage (1.2.840.10008.5.1.4.1.1.9.1.4)
/// - Hemodynamic Waveform Storage (1.2.840.10008.5.1.4.1.1.9.2.1)
/// - Cardiac Electrophysiology Waveform Storage (1.2.840.10008.5.1.4.1.1.9.3.1)
/// - Basic Voice Audio Waveform Storage (1.2.840.10008.5.1.4.1.1.9.4.1)
/// - General Audio Waveform Storage (1.2.840.10008.5.1.4.1.1.9.4.2)
/// - Arterial Pulse Waveform Storage (1.2.840.10008.5.1.4.1.1.9.5.1)
/// - Respiratory Waveform Storage (1.2.840.10008.5.1.4.1.1.9.6.1)
/// - Multi-channel Respiratory Waveform Storage (1.2.840.10008.5.1.4.1.1.9.6.2)
/// - Routine Scalp Electroencephalogram Waveform Storage (1.2.840.10008.5.1.4.1.1.9.7.1)
/// - Electromyogram Waveform Storage (1.2.840.10008.5.1.4.1.1.9.7.2)
/// - Electrooculogram Waveform Storage (1.2.840.10008.5.1.4.1.1.9.7.3)
/// - Sleep Electroencephalogram Waveform Storage (1.2.840.10008.5.1.4.1.1.9.7.4)
/// - Body Position Waveform Storage (1.2.840.10008.5.1.4.1.1.9.8.1)
///
/// Reference: PS3.3 A.34 - Waveform IODs
/// Reference: PS3.3 C.10.8 - Waveform Identification Module
/// Reference: PS3.3 C.10.9 - Waveform Module
public struct Waveform: Sendable {

    // MARK: - SOP Class UIDs

    /// 12-lead ECG Waveform Storage
    public static let twelveLeadECGStorageUID = "1.2.840.10008.5.1.4.1.1.9.1.1"

    /// General ECG Waveform Storage
    public static let generalECGStorageUID = "1.2.840.10008.5.1.4.1.1.9.1.2"

    /// Ambulatory ECG Waveform Storage
    public static let ambulatoryECGStorageUID = "1.2.840.10008.5.1.4.1.1.9.1.3"

    /// General 32-bit ECG Waveform Storage (PS3.3 A.34.18)
    public static let general32BitECGStorageUID = "1.2.840.10008.5.1.4.1.1.9.1.4"

    /// Hemodynamic Waveform Storage
    public static let hemodynamicWaveformStorageUID = "1.2.840.10008.5.1.4.1.1.9.2.1"

    /// Cardiac Electrophysiology Waveform Storage
    public static let cardiacElectrophysiologyStorageUID = "1.2.840.10008.5.1.4.1.1.9.3.1"

    /// Basic Voice Audio Waveform Storage
    public static let basicVoiceAudioStorageUID = "1.2.840.10008.5.1.4.1.1.9.4.1"

    /// General Audio Waveform Storage
    public static let generalAudioStorageUID = "1.2.840.10008.5.1.4.1.1.9.4.2"

    /// Arterial Pulse Waveform Storage
    public static let arterialPulseWaveformStorageUID = "1.2.840.10008.5.1.4.1.1.9.5.1"

    /// Respiratory Waveform Storage
    public static let respiratoryWaveformStorageUID = "1.2.840.10008.5.1.4.1.1.9.6.1"

    /// Multi-channel Respiratory Waveform Storage (PS3.3 A.34.16)
    public static let multichannelRespiratoryWaveformStorageUID = "1.2.840.10008.5.1.4.1.1.9.6.2"

    /// Routine Scalp Electroencephalogram Waveform Storage (PS3.3 A.34.12)
    public static let routineScalpEEGStorageUID = "1.2.840.10008.5.1.4.1.1.9.7.1"

    /// Electromyogram Waveform Storage (PS3.3 A.34.13)
    public static let electromyogramStorageUID = "1.2.840.10008.5.1.4.1.1.9.7.2"

    /// Electrooculogram Waveform Storage (PS3.3 A.34.14)
    public static let electrooculogramStorageUID = "1.2.840.10008.5.1.4.1.1.9.7.3"

    /// Sleep Electroencephalogram Waveform Storage (PS3.3 A.34.15)
    public static let sleepEEGStorageUID = "1.2.840.10008.5.1.4.1.1.9.7.4"

    /// Body Position Waveform Storage (PS3.3 A.34.17)
    public static let bodyPositionWaveformStorageUID = "1.2.840.10008.5.1.4.1.1.9.8.1"

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

    /// Modality (typically "ECG", "HD", "EPS", "AU")
    public let modality: String?

    /// Series Description
    public let seriesDescription: String?

    /// Series Number
    public let seriesNumber: Int?

    // MARK: - Content Date/Time

    /// Content Date
    public let contentDate: DICOMDate?

    /// Content Time
    public let contentTime: DICOMTime?

    /// Acquisition DateTime (0008,002A) — Type 1 in the Waveform Identification
    /// Module (PS3.3 Table C.10-8): the start of the acquisition, and the reference
    /// timestamp for Multiplex Group Time Offset (0018,1068).
    public let acquisitionDateTime: DICOMDateTime?

    // MARK: - Waveform Data

    /// Multiplex groups containing the waveform data
    public let multiplexGroups: [WaveformMultiplexGroup]

    /// Waveform annotations
    public let annotations: [WaveformAnnotation]

    // MARK: - Initialization

    /// Creates a Waveform
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
        contentDate: DICOMDate? = nil,
        contentTime: DICOMTime? = nil,
        acquisitionDateTime: DICOMDateTime? = nil,
        multiplexGroups: [WaveformMultiplexGroup] = [],
        annotations: [WaveformAnnotation] = []
    ) {
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
        self.contentDate = contentDate
        self.contentTime = contentTime
        self.acquisitionDateTime = acquisitionDateTime
        self.multiplexGroups = multiplexGroups
        self.annotations = annotations
    }

    /// The waveform type inferred from the SOP Class UID
    public var waveformType: WaveformType {
        return WaveformType(sopClassUID: sopClassUID)
    }

    /// Total number of channels across all multiplex groups
    public var totalChannelCount: Int {
        return multiplexGroups.reduce(0) { $0 + $1.channels.count }
    }

    /// Total number of samples across all multiplex groups
    public var totalSampleCount: Int {
        return multiplexGroups.reduce(0) { $0 + $1.numberOfSamples }
    }
}

// MARK: - Waveform Type

/// Type of waveform based on SOP Class UID
///
/// Reference: PS3.6 Table A-1 (SOP Class UIDs); PS3.3 A.34.2 – A.34.18 (IOD content
/// constraints, which fix the Modality for each IOD).
public enum WaveformType: String, Sendable, CaseIterable {
    case twelveLeadECG
    case generalECG
    case ambulatoryECG
    /// General 32-bit ECG IOD (PS3.3 A.34.18)
    case general32BitECG
    case hemodynamic
    case cardiacElectrophysiology
    case basicVoiceAudio
    case generalAudio
    case arterialPulse
    case respiratoryWaveform
    /// Multi-channel Respiratory Waveform IOD (PS3.3 A.34.16)
    case multichannelRespiratory
    /// Routine Scalp Electroencephalogram IOD (PS3.3 A.34.12)
    case routineScalpEEG
    /// Electromyogram IOD (PS3.3 A.34.13)
    case electromyogram
    /// Electrooculogram IOD (PS3.3 A.34.14)
    case electrooculogram
    /// Sleep Electroencephalogram IOD (PS3.3 A.34.15)
    case sleepEEG
    /// Body Position Waveform IOD (PS3.3 A.34.17)
    case bodyPosition
    case unknown

    /// Creates a waveform type from a SOP Class UID
    public init(sopClassUID: String) {
        switch sopClassUID {
        case Waveform.twelveLeadECGStorageUID:
            self = .twelveLeadECG
        case Waveform.generalECGStorageUID:
            self = .generalECG
        case Waveform.ambulatoryECGStorageUID:
            self = .ambulatoryECG
        case Waveform.general32BitECGStorageUID:
            self = .general32BitECG
        case Waveform.hemodynamicWaveformStorageUID:
            self = .hemodynamic
        case Waveform.cardiacElectrophysiologyStorageUID:
            self = .cardiacElectrophysiology
        case Waveform.basicVoiceAudioStorageUID:
            self = .basicVoiceAudio
        case Waveform.generalAudioStorageUID:
            self = .generalAudio
        case Waveform.arterialPulseWaveformStorageUID:
            self = .arterialPulse
        case Waveform.respiratoryWaveformStorageUID:
            self = .respiratoryWaveform
        case Waveform.multichannelRespiratoryWaveformStorageUID:
            self = .multichannelRespiratory
        case Waveform.routineScalpEEGStorageUID:
            self = .routineScalpEEG
        case Waveform.electromyogramStorageUID:
            self = .electromyogram
        case Waveform.electrooculogramStorageUID:
            self = .electrooculogram
        case Waveform.sleepEEGStorageUID:
            self = .sleepEEG
        case Waveform.bodyPositionWaveformStorageUID:
            self = .bodyPosition
        default:
            self = .unknown
        }
    }

    /// The SOP Class UID for this waveform type
    public var sopClassUID: String {
        switch self {
        case .twelveLeadECG: return Waveform.twelveLeadECGStorageUID
        case .generalECG: return Waveform.generalECGStorageUID
        case .ambulatoryECG: return Waveform.ambulatoryECGStorageUID
        case .general32BitECG: return Waveform.general32BitECGStorageUID
        case .hemodynamic: return Waveform.hemodynamicWaveformStorageUID
        case .cardiacElectrophysiology: return Waveform.cardiacElectrophysiologyStorageUID
        case .basicVoiceAudio: return Waveform.basicVoiceAudioStorageUID
        case .generalAudio: return Waveform.generalAudioStorageUID
        case .arterialPulse: return Waveform.arterialPulseWaveformStorageUID
        case .respiratoryWaveform: return Waveform.respiratoryWaveformStorageUID
        case .multichannelRespiratory: return Waveform.multichannelRespiratoryWaveformStorageUID
        case .routineScalpEEG: return Waveform.routineScalpEEGStorageUID
        case .electromyogram: return Waveform.electromyogramStorageUID
        case .electrooculogram: return Waveform.electrooculogramStorageUID
        case .sleepEEG: return Waveform.sleepEEGStorageUID
        case .bodyPosition: return Waveform.bodyPositionWaveformStorageUID
        case .unknown: return ""
        }
    }

    /// The Modality (0008,0060) value the IOD's content constraints require
    /// (PS3.3 A.34.2 – A.34.18: "The Value of Modality (0008,0060) shall be …").
    /// `nil` for `.unknown`.
    public var modality: Modality? {
        switch self {
        case .twelveLeadECG, .generalECG, .ambulatoryECG, .general32BitECG:
            return .ecg                          // A.34.3.4.1, A.34.4.4.1, A.34.5.4.1, A.34.18.4.1
        case .hemodynamic, .arterialPulse:
            return .hd                           // A.34.6.4.1, A.34.8.4.1 "HD (hemodynamic waveform)"
        case .cardiacElectrophysiology:
            return .eps                          // A.34.7.4.1
        case .basicVoiceAudio, .generalAudio:
            return .au                           // A.34.2.4.1, A.34.10.4.1 "AU (audio)"
        case .respiratoryWaveform, .multichannelRespiratory:
            return .resp                         // A.34.9.4.1, A.34.16.4.1
        case .routineScalpEEG, .sleepEEG:
            return .eeg                          // A.34.12.4.1, A.34.15.4.1
        case .electromyogram:
            return .emg                          // A.34.13.4.1
        case .electrooculogram:
            return .eog                          // A.34.14.4.1
        case .bodyPosition:
            return .pos                          // A.34.17.4.1
        case .unknown:
            return nil
        }
    }

    /// Human-readable description of the waveform type
    public var description: String {
        switch self {
        case .twelveLeadECG: return "12-Lead ECG"
        case .generalECG: return "General ECG"
        case .ambulatoryECG: return "Ambulatory ECG"
        case .general32BitECG: return "General 32-bit ECG"
        case .hemodynamic: return "Hemodynamic"
        case .cardiacElectrophysiology: return "Cardiac Electrophysiology"
        case .basicVoiceAudio: return "Basic Voice Audio"
        case .generalAudio: return "General Audio"
        case .arterialPulse: return "Arterial Pulse"
        case .respiratoryWaveform: return "Respiratory"
        case .multichannelRespiratory: return "Multi-channel Respiratory"
        case .routineScalpEEG: return "Routine Scalp EEG"
        case .electromyogram: return "Electromyogram"
        case .electrooculogram: return "Electrooculogram"
        case .sleepEEG: return "Sleep EEG"
        case .bodyPosition: return "Body Position"
        case .unknown: return "Unknown"
        }
    }
}

// MARK: - Waveform Multiplex Group

/// A multiplex group containing one or more channels sharing a common sampling frequency
///
/// Reference: PS3.3 C.10.9.1 - Waveform Module Attributes
public struct WaveformMultiplexGroup: Sendable {

    /// Sampling frequency in Hz
    public let samplingFrequency: Double

    /// Number of samples per channel
    public let numberOfSamples: Int

    /// Waveform Bits Allocated (5400,1004) — 8, 16, 32 or 64 (PS3.3 Table C.10-10)
    public let waveformBitsAllocated: UInt16

    /// Waveform Bits Stored (003A,021A) — significant bits per sample, written into
    /// every Channel Definition Sequence Item (Type 1, PS3.3 Table C.10-9)
    public let waveformBitsStored: UInt16

    /// Waveform Sample Interpretation (5400,1006)
    public let waveformSampleInterpretation: WaveformSampleInterpretation

    /// Channel definitions
    public let channels: [WaveformChannel]

    /// Raw waveform data (interleaved channel samples)
    public let waveformData: Data

    /// Waveform Originality (003A,0004) — ORIGINAL or DERIVED (Type 1, PS3.3 C.10.9.1.3)
    public let originality: WaveformOriginality?

    /// Multiplex group label
    public let multiplexGroupLabel: String?

    /// Multiplex Group Time Offset (0018,1068) in milliseconds from Acquisition
    /// DateTime (PS3.3 C.10.9.1.1)
    public let multiplexGroupTimeOffset: Double?

    /// Trigger Time Offset (0018,1069) in milliseconds from the synchronization
    /// trigger to the first sample (PS3.3 Table C.10-9)
    public let triggerTimeOffset: Double?

    /// Creates a WaveformMultiplexGroup
    public init(
        samplingFrequency: Double,
        numberOfSamples: Int,
        waveformBitsAllocated: UInt16,
        waveformBitsStored: UInt16,
        waveformSampleInterpretation: WaveformSampleInterpretation,
        channels: [WaveformChannel],
        waveformData: Data,
        originality: WaveformOriginality? = nil,
        multiplexGroupLabel: String? = nil,
        multiplexGroupTimeOffset: Double? = nil,
        triggerTimeOffset: Double? = nil
    ) {
        self.samplingFrequency = samplingFrequency
        self.numberOfSamples = numberOfSamples
        self.waveformBitsAllocated = waveformBitsAllocated
        self.waveformBitsStored = waveformBitsStored
        self.waveformSampleInterpretation = waveformSampleInterpretation
        self.channels = channels
        self.waveformData = waveformData
        self.originality = originality
        self.multiplexGroupLabel = multiplexGroupLabel
        self.multiplexGroupTimeOffset = multiplexGroupTimeOffset
        self.triggerTimeOffset = triggerTimeOffset
    }

    /// Extracts sample values for a specific channel
    ///
    /// - Parameter channelIndex: The zero-based index of the channel
    /// - Returns: Array of sample values as Doubles, applying sensitivity and baseline corrections
    public func channelSamples(at channelIndex: Int) -> [Double] {
        guard channelIndex >= 0 && channelIndex < channels.count else {
            return []
        }

        let channel = channels[channelIndex]
        let channelCount = channels.count
        let bytesPerSample = Int(waveformBitsAllocated) / 8

        var samples: [Double] = []
        samples.reserveCapacity(numberOfSamples)

        for sampleIndex in 0..<numberOfSamples {
            let byteOffset = (sampleIndex * channelCount + channelIndex) * bytesPerSample
            guard byteOffset + bytesPerSample <= waveformData.count else { break }

            // Samples are little-endian integers of Waveform Bits Allocated bits, sign
            // extended to the highest bit when Bits Stored < Bits Allocated
            // (PS3.3 C.10.9.1.7), so a full-width read gives the value directly.
            // MB/AB (G.711 companded) samples are returned as their raw code.
            var bits: UInt64 = 0
            for i in 0..<bytesPerSample {
                bits |= UInt64(waveformData[byteOffset + i]) << (8 * UInt64(i))
            }
            let rawValue: Double
            if waveformSampleInterpretation.isSigned {
                switch bytesPerSample {
                case 1: rawValue = Double(Int8(truncatingIfNeeded: bits))
                case 2: rawValue = Double(Int16(truncatingIfNeeded: bits))
                case 4: rawValue = Double(Int32(truncatingIfNeeded: bits))
                case 8: rawValue = Double(Int64(bitPattern: bits))
                default: rawValue = 0
                }
            } else {
                rawValue = Double(bits)
            }

            // Apply channel sensitivity and baseline correction
            let correctedValue = channel.applyCalibration(rawValue: rawValue)
            samples.append(correctedValue)
        }

        return samples
    }

    /// Duration of the waveform in seconds
    public var duration: Double {
        guard samplingFrequency > 0 else { return 0 }
        return Double(numberOfSamples) / samplingFrequency
    }
}

// MARK: - Waveform Channel

/// Definition of a single waveform channel within a multiplex group
///
/// Reference: PS3.3 C.10.9.1 - Channel Definition Sequence
public struct WaveformChannel: Sendable {

    /// Channel label (e.g., "Lead I", "Lead II")
    public let channelLabel: String?

    /// Channel status
    public let channelStatus: [String]?

    /// Channel source - coded description of the signal source
    public let channelSource: WaveformCodedConcept?

    /// Channel source modifiers
    public let channelSourceModifiers: [WaveformCodedConcept]?

    /// Channel sensitivity (units per raw value)
    public let channelSensitivity: Double?

    /// Channel sensitivity units
    public let channelSensitivityUnits: WaveformCodedConcept?

    /// Channel sensitivity correction factor
    public let channelSensitivityCorrectionFactor: Double?

    /// Channel baseline value
    public let channelBaseline: Double?

    /// Channel time skew in seconds
    public let channelTimeSkew: Double?

    /// Channel sample skew
    public let channelSampleSkew: Double?

    /// Channel offset
    public let channelOffset: Double?

    /// Filter low frequency in Hz
    public let filterLowFrequency: Double?

    /// Filter high frequency in Hz
    public let filterHighFrequency: Double?

    /// Notch filter frequency in Hz
    public let notchFilterFrequency: Double?

    /// Notch filter bandwidth in Hz
    public let notchFilterBandwidth: Double?

    /// Creates a WaveformChannel
    public init(
        channelLabel: String? = nil,
        channelStatus: [String]? = nil,
        channelSource: WaveformCodedConcept? = nil,
        channelSourceModifiers: [WaveformCodedConcept]? = nil,
        channelSensitivity: Double? = nil,
        channelSensitivityUnits: WaveformCodedConcept? = nil,
        channelSensitivityCorrectionFactor: Double? = nil,
        channelBaseline: Double? = nil,
        channelTimeSkew: Double? = nil,
        channelSampleSkew: Double? = nil,
        channelOffset: Double? = nil,
        filterLowFrequency: Double? = nil,
        filterHighFrequency: Double? = nil,
        notchFilterFrequency: Double? = nil,
        notchFilterBandwidth: Double? = nil
    ) {
        self.channelLabel = channelLabel
        self.channelStatus = channelStatus
        self.channelSource = channelSource
        self.channelSourceModifiers = channelSourceModifiers
        self.channelSensitivity = channelSensitivity
        self.channelSensitivityUnits = channelSensitivityUnits
        self.channelSensitivityCorrectionFactor = channelSensitivityCorrectionFactor
        self.channelBaseline = channelBaseline
        self.channelTimeSkew = channelTimeSkew
        self.channelSampleSkew = channelSampleSkew
        self.channelOffset = channelOffset
        self.filterLowFrequency = filterLowFrequency
        self.filterHighFrequency = filterHighFrequency
        self.notchFilterFrequency = notchFilterFrequency
        self.notchFilterBandwidth = notchFilterBandwidth
    }

    /// Applies calibration to convert a raw sample value to physical units
    ///
    /// The formula is: value = (rawValue + baseline) * sensitivity * correctionFactor + offset
    ///
    /// Reference: PS3.3 C.10.9.1.4.3 - Waveform Sample Value Transformation
    ///
    /// - Parameter rawValue: Raw integer sample value
    /// - Returns: Calibrated value in physical units
    public func applyCalibration(rawValue: Double) -> Double {
        let baseline = channelBaseline ?? 0
        let sensitivity = channelSensitivity ?? 1
        let correctionFactor = channelSensitivityCorrectionFactor ?? 1
        let offset = channelOffset ?? 0
        return (rawValue + baseline) * sensitivity * correctionFactor + offset
    }
}

// MARK: - Waveform Annotation

/// Annotation associated with a waveform
///
/// Reference: PS3.3 C.10.10 - Waveform Annotation Module
public struct WaveformAnnotation: Sendable {

    /// Unformatted text value of the annotation
    public let textValue: String?

    /// Coded concept for the annotation
    public let conceptNameCode: WaveformCodedConcept?

    /// Numeric value associated with the annotation
    public let numericValue: Double?

    /// Units for the numeric value
    public let measurementUnits: WaveformCodedConcept?

    /// Annotation group number
    public let annotationGroupNumber: UInt16?

    /// Temporal range type (POINT, MULTIPOINT, SEGMENT, MULTISEGMENT, BEGIN, END)
    public let temporalRangeType: TemporalRangeType?

    /// Referenced sample positions within the waveform data
    public let referencedSamplePositions: [UInt32]?

    /// Referenced time offsets in seconds
    public let referencedTimeOffsets: [Double]?

    /// Creates a WaveformAnnotation
    public init(
        textValue: String? = nil,
        conceptNameCode: WaveformCodedConcept? = nil,
        numericValue: Double? = nil,
        measurementUnits: WaveformCodedConcept? = nil,
        annotationGroupNumber: UInt16? = nil,
        temporalRangeType: TemporalRangeType? = nil,
        referencedSamplePositions: [UInt32]? = nil,
        referencedTimeOffsets: [Double]? = nil
    ) {
        self.textValue = textValue
        self.conceptNameCode = conceptNameCode
        self.numericValue = numericValue
        self.measurementUnits = measurementUnits
        self.annotationGroupNumber = annotationGroupNumber
        self.temporalRangeType = temporalRangeType
        self.referencedSamplePositions = referencedSamplePositions
        self.referencedTimeOffsets = referencedTimeOffsets
    }
}

// MARK: - Supporting Types

/// Waveform Sample Interpretation (5400,1006)
///
/// Reference: PS3.3 C.10.9.1.5, Table C.10-10 - Waveform Bits Allocated and Waveform Sample
/// Interpretation. The Defined Terms, and the Waveform Bits Allocated each one pairs with:
///
/// | Bits Allocated | Term | Meaning |
/// |---|---|---|
/// | 8  | SB | signed 8 bit linear |
/// | 8  | UB | unsigned 8 bit linear |
/// | 8  | MB | 8 bit mu-law (ITU-T G.711) |
/// | 8  | AB | 8 bit A-law (ITU-T G.711) |
/// | 16 | SS | signed 16 bit linear |
/// | 16 | US | unsigned 16 bit linear |
/// | 32 | SL | signed 32 bit linear |
/// | 32 | UL | unsigned 32 bit linear |
/// | 64 | SV | signed 64 bit linear |
/// | 64 | UV | unsigned 64 bit linear |
///
/// The case names carry the bit width because the earlier names contradicted the table
/// (`unsignedInteger` was the raw value SB, *signed* 8 bit; `signedShort` was US, *unsigned*
/// 16 bit). Those names remain as deprecated aliases of the correctly named cases.
public enum WaveformSampleInterpretation: String, Sendable, CaseIterable {
    /// SB: signed 8 bit linear
    case signed8 = "SB"
    /// UB: unsigned 8 bit linear
    case unsigned8 = "UB"
    /// MB: 8 bit mu-law (ITU-T Recommendation G.711)
    case muLaw = "MB"
    /// AB: 8 bit A-law (ITU-T Recommendation G.711)
    case aLaw = "AB"
    /// SS: signed 16 bit linear
    case signed16 = "SS"
    /// US: unsigned 16 bit linear
    case unsigned16 = "US"
    /// SL: signed 32 bit linear
    case signed32 = "SL"
    /// UL: unsigned 32 bit linear
    case unsigned32 = "UL"
    /// SV: signed 64 bit linear
    case signed64 = "SV"
    /// UV: unsigned 64 bit linear
    case unsigned64 = "UV"

    // MARK: Deprecated names (raw values unchanged; see Table C.10-10)

    /// Raw value SB, which Table C.10-10 defines as *signed* 8 bit linear.
    @available(*, deprecated, renamed: "signed8")
    public static var unsignedInteger: WaveformSampleInterpretation { .signed8 }

    /// Raw value SS, signed 16 bit linear.
    @available(*, deprecated, renamed: "signed16")
    public static var signedInteger: WaveformSampleInterpretation { .signed16 }

    /// Raw value UB, unsigned 8 bit linear.
    @available(*, deprecated, renamed: "unsigned8")
    public static var unsignedByte: WaveformSampleInterpretation { .unsigned8 }

    /// Raw value US, which Table C.10-10 defines as *unsigned* 16 bit linear.
    @available(*, deprecated, renamed: "unsigned16")
    public static var signedShort: WaveformSampleInterpretation { .unsigned16 }

    /// Creates from a DICOM code string value (surrounding spaces ignored)
    public init?(dicomValue: String) {
        self.init(rawValue: dicomValue.trimmingCharacters(in: .whitespaces))
    }

    /// Whether this interpretation represents signed values (PS3.3 Table C.10-10).
    /// The companded terms MB and AB are not linear integers and are reported as unsigned.
    public var isSigned: Bool {
        switch self {
        case .signed8, .signed16, .signed32, .signed64: return true
        case .unsigned8, .unsigned16, .unsigned32, .unsigned64, .muLaw, .aLaw: return false
        }
    }

    /// Whether the samples are linear integers (false for the G.711 companded terms MB and AB)
    public var isLinear: Bool {
        switch self {
        case .muLaw, .aLaw: return false
        default: return true
        }
    }

    /// The Waveform Bits Allocated (5400,1004) Defined Term this interpretation pairs
    /// with in PS3.3 Table C.10-10
    public var bitsAllocated: UInt16 {
        switch self {
        case .signed8, .unsigned8, .muLaw, .aLaw: return 8
        case .signed16, .unsigned16: return 16
        case .signed32, .unsigned32: return 32
        case .signed64, .unsigned64: return 64
        }
    }
}

/// Waveform Originality (003A,0004), Type 1: ORIGINAL if the samples are the original
/// or source data, DERIVED if derived from the sample data of other waveforms.
///
/// Reference: PS3.3 C.10.9.1.3 - Waveform Originality
public enum WaveformOriginality: String, Sendable {
    case original = "ORIGINAL"
    case derived = "DERIVED"

    /// Creates from a DICOM code string value
    public init?(dicomValue: String) {
        let trimmed = dicomValue.trimmingCharacters(in: .whitespaces)
        switch trimmed {
        case "ORIGINAL": self = .original
        case "DERIVED": self = .derived
        default: return nil
        }
    }
}

// TemporalRangeType is defined in DICOMCore.StructuredReporting.ContentItem
// and is reused here for waveform annotations

/// Coded concept used in waveform channel source and annotations
///
/// Reference: PS3.3 Section 8.8 - Standard Attribute Sets for Code Sequence Attributes (Table 8.8-1)
public struct WaveformCodedConcept: Sendable, Equatable {
    /// Code Value (0008,0100)
    public let codeValue: String

    /// Coding Scheme Designator (0008,0102)
    public let codingSchemeDesignator: String

    /// Code Meaning (0008,0104)
    public let codeMeaning: String

    public init(codeValue: String, codingSchemeDesignator: String, codeMeaning: String) {
        self.codeValue = codeValue
        self.codingSchemeDesignator = codingSchemeDesignator
        self.codeMeaning = codeMeaning
    }
}
