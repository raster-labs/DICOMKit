// SpecializedModalityModel.swift
// DICOMStudio
//
// DICOM Studio — Specialized modality data models for RT, Segmentation,
// Parametric Maps, Waveforms, Video, Encapsulated Documents, Secondary Capture, and WSI
// NEMA-verified: 2026a, checked 2026-10-05 — enum raw values diffed by script against PS3.3 2026a: RTROIType 7 cases vs RT ROI Interpreted Type (3006,00A4) Defined Terms (Table C.8-44: 6 match, OTHER is not a term, 19 terms absent — P-STUDIO-RT-ROI-TYPES); RTDoseUnits vs Dose Units (3004,0002) (Table C.8-39: GY matches, CGY is not a term and RELATIVE is absent — P-STUDIO-RT-DOSE-UNITS); RTRadiationType 4 vs Radiation Type (300A,00C6) Defined Terms (Table C.8-50: 4/4); SegmentAlgorithmType 3 vs Segment Algorithm Type (0062,0008) (Table C.8.20-4: 3/3); EncapsulatedDocumentType MIME types vs the MIME Type of Encapsulated Document Enumerated Values of A.45.1.4.1, A.45.2.4 and A.85.1-A.85.3 (5: 4 match, CDA corrected to "text/XML"); SecondaryCaptureDisplayType 5 SOP Class UIDs vs PS3.6 2026a Table A-1 (5/5); the rest (colours, colormaps, display state, SUV input, video) carries no standard data

import Foundation

// MARK: - RT Structure Set

/// An ROI (Region of Interest) in an RT Structure Set.
public struct RTStructureSetROI: Sendable, Equatable, Hashable {
    public let id: Int
    public let name: String
    public let roiType: RTROIType
    public let color: RTColor
    public let description: String?
    public var isVisible: Bool

    public init(id: Int, name: String, roiType: RTROIType, color: RTColor,
                description: String? = nil, isVisible: Bool = true) {
        self.id = id
        self.name = name
        self.roiType = roiType
        self.color = color
        self.description = description
        self.isVisible = isVisible
    }
}

/// Types of RT ROIs: the RT ROI Interpreted Type (3006,00A4) Defined Terms of PS3.3 2026a
/// C.8.8.8.1 (RT ROI Observations Module, Table C.8-44) — all 25 are carried, in the order the
/// standard lists them (P-STUDIO-RT-ROI-TYPES).
///
/// `init(rawValue:)` returns nil for a value that is not one of the 25 terms, including "OTHER";
/// the deprecated `other` case is kept for source compatibility only and is not in `allCases`.
public enum RTROIType: String, Sendable, Equatable, Hashable, CaseIterable {
    /// EXTERNAL — external patient contour.
    case external = "EXTERNAL"
    /// PTV — Planning Target Volume (ICRU 50).
    case ptv = "PTV"
    /// CTV — Clinical Target Volume (ICRU 50).
    case ctv = "CTV"
    /// GTV — Gross Tumor Volume (ICRU 50).
    case gtv = "GTV"
    /// TREATED_VOLUME — Treated Volume (ICRU 50).
    case treatedVolume = "TREATED_VOLUME"
    /// IRRAD_VOLUME — Irradiated Volume (ICRU 50).
    case irradiatedVolume = "IRRAD_VOLUME"
    /// OAR — Organ at Risk (ICRU 50).
    case oar = "OAR"
    /// BOLUS — patient bolus to be used for external beam therapy.
    case bolus = "BOLUS"
    /// AVOIDANCE — region in which dose is to be minimized.
    case avoidance = "AVOIDANCE"
    /// ORGAN — patient organ.
    case organ = "ORGAN"
    /// MARKER — patient marker or marker on a localizer.
    case marker = "MARKER"
    /// REGISTRATION — registration ROI.
    case registration = "REGISTRATION"
    /// ISOCENTER — treatment isocenter to be used for external beam therapy.
    case isocenter = "ISOCENTER"
    /// CONTRAST_AGENT — volume into which a contrast agent has been injected.
    case contrastAgent = "CONTRAST_AGENT"
    /// CAVITY — patient anatomical cavity.
    case cavity = "CAVITY"
    /// BRACHY_CHANNEL — brachytherapy channel.
    case brachyChannel = "BRACHY_CHANNEL"
    /// BRACHY_ACCESSORY — brachytherapy accessory device.
    case brachyAccessory = "BRACHY_ACCESSORY"
    /// BRACHY_SRC_APP — brachytherapy source applicator.
    case brachySourceApplicator = "BRACHY_SRC_APP"
    /// BRACHY_CHNL_SHLD — brachytherapy channel shield.
    case brachyChannelShield = "BRACHY_CHNL_SHLD"
    /// SUPPORT — external patient support device.
    case support = "SUPPORT"
    /// FIXATION — external patient fixation or immobilization device.
    case fixation = "FIXATION"
    /// DOSE_REGION — ROI to be used as a dose reference.
    case doseRegion = "DOSE_REGION"
    /// CONTROL — ROI to be used in control of dose optimization and calculation.
    case control = "CONTROL"
    /// DOSE_MEASUREMENT — ROI representing a dose measurement device, such as a chamber or TLD.
    case doseMeasurement = "DOSE_MEASUREMENT"
    /// DEVICE — device not addressed by another Defined Term.
    case device = "DEVICE"
    /// Not an RT ROI Interpreted Type Defined Term; never produced by `init(rawValue:)`.
    @available(*, deprecated, message: "OTHER is not an RT ROI Interpreted Type Defined Term (PS3.3 2026a C.8.8.8.1); use an optional RTROIType, nil for an unknown or empty value")
    case other = "OTHER"

    /// The 25 Defined Terms of PS3.3 2026a C.8.8.8.1, in the standard's order (the deprecated
    /// `other` is not included).
    public static let allCases: [RTROIType] = [
        .external, .ptv, .ctv, .gtv, .treatedVolume, .irradiatedVolume, .oar, .bolus, .avoidance,
        .organ, .marker, .registration, .isocenter, .contrastAgent, .cavity, .brachyChannel,
        .brachyAccessory, .brachySourceApplicator, .brachyChannelShield, .support, .fixation,
        .doseRegion, .control, .doseMeasurement, .device,
    ]

    /// Creates a type from an RT ROI Interpreted Type value; nil when the value is not one of the
    /// 25 Defined Terms (an unknown value, an empty value or the legacy app value "OTHER").
    public init?(rawValue: String) {
        guard let match = Self.allCases.first(where: { $0.rawValue == rawValue }) else { return nil }
        self = match
    }

    /// Human-readable display name (the PS3.3 2026a C.8.8.8.1 description).
    public var displayName: String {
        switch self {
        case .external: return "External Patient Contour"
        case .ptv: return "Planning Target Volume"
        case .ctv: return "Clinical Target Volume"
        case .gtv: return "Gross Tumor Volume"
        case .treatedVolume: return "Treated Volume"
        case .irradiatedVolume: return "Irradiated Volume"
        case .oar: return "Organ at Risk"
        case .bolus: return "Bolus"
        case .avoidance: return "Avoidance Region"
        case .organ: return "Organ"
        case .marker: return "Marker"
        case .registration: return "Registration"
        case .isocenter: return "Isocenter"
        case .contrastAgent: return "Contrast Agent"
        case .cavity: return "Cavity"
        case .brachyChannel: return "Brachy Channel"
        case .brachyAccessory: return "Brachy Accessory"
        case .brachySourceApplicator: return "Brachy Source Applicator"
        case .brachyChannelShield: return "Brachy Channel Shield"
        case .support: return "Support"
        case .fixation: return "Fixation"
        case .doseRegion: return "Dose Region"
        case .control: return "Control"
        case .doseMeasurement: return "Dose Measurement"
        case .device: return "Device"
        default: return "Other"   // deprecated `other`
        }
    }

    /// SF Symbol name for this ROI type.
    public var sfSymbol: String {
        switch self {
        case .ptv: return "circle.dashed"
        case .ctv: return "circle.dotted"
        case .gtv: return "circle.fill"
        case .treatedVolume, .irradiatedVolume: return "circle.circle"
        case .oar: return "exclamationmark.triangle"
        case .organ: return "heart"
        case .avoidance: return "nosign"
        case .external: return "person.fill"
        case .bolus: return "square.stack"
        case .marker: return "mappin"
        case .registration: return "scope"
        case .isocenter: return "plus.circle"
        case .contrastAgent: return "drop.fill"
        case .cavity: return "circle.dotted.circle"
        case .brachyChannel, .brachyChannelShield: return "line.diagonal"
        case .brachyAccessory, .brachySourceApplicator: return "wrench.and.screwdriver"
        case .support: return "rectangle.fill"
        case .fixation: return "lock.fill"
        case .doseRegion, .doseMeasurement: return "gauge.medium"
        case .control: return "slider.horizontal.3"
        case .device: return "cpu"
        default: return "questionmark.circle"   // deprecated `other`
        }
    }
}

/// An RGB+alpha color for RT visualization.
public struct RTColor: Sendable, Equatable, Hashable {
    /// Red component, 0–1.
    public let red: Double
    /// Green component, 0–1.
    public let green: Double
    /// Blue component, 0–1.
    public let blue: Double
    /// Alpha component, 0–1.
    public let alpha: Double

    public init(red: Double, green: Double, blue: Double, alpha: Double = 1.0) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    // MARK: Static Presets
    public static let red    = RTColor(red: 1.0, green: 0.0, blue: 0.0)
    public static let green  = RTColor(red: 0.0, green: 0.8, blue: 0.0)
    public static let blue   = RTColor(red: 0.0, green: 0.0, blue: 1.0)
    public static let yellow = RTColor(red: 1.0, green: 1.0, blue: 0.0)
    public static let orange = RTColor(red: 1.0, green: 0.5, blue: 0.0)
    public static let pink   = RTColor(red: 1.0, green: 0.4, blue: 0.7)
    public static let purple = RTColor(red: 0.6, green: 0.0, blue: 0.8)
    public static let cyan   = RTColor(red: 0.0, green: 1.0, blue: 1.0)
    public static let white  = RTColor(red: 1.0, green: 1.0, blue: 1.0)
    public static let black  = RTColor(red: 0.0, green: 0.0, blue: 0.0)
}

// MARK: - RT Plan

/// A beam in an RT Plan.
public struct RTBeam: Sendable, Equatable, Hashable {
    public let beamID: Int
    public let beamName: String?
    public let radiationType: RTRadiationType
    public let gantryAngle: Double
    public let collimatorAngle: Double
    public let couchAngle: Double
    public let energy: Double?
    public let dose: Double?
    public let numberOfControlPoints: Int

    public init(beamID: Int, beamName: String? = nil, radiationType: RTRadiationType,
                gantryAngle: Double, collimatorAngle: Double, couchAngle: Double,
                energy: Double? = nil, dose: Double? = nil, numberOfControlPoints: Int) {
        self.beamID = beamID
        self.beamName = beamName
        self.radiationType = radiationType
        self.gantryAngle = gantryAngle
        self.collimatorAngle = collimatorAngle
        self.couchAngle = couchAngle
        self.energy = energy
        self.dose = dose
        self.numberOfControlPoints = numberOfControlPoints
    }
}

/// Radiation type for an RT beam.
public enum RTRadiationType: String, Sendable, Equatable, Hashable, CaseIterable {
    case photon   = "PHOTON"
    case electron = "ELECTRON"
    case neutron  = "NEUTRON"
    case proton   = "PROTON"

    public var displayName: String {
        switch self {
        case .photon:   return "Photon"
        case .electron: return "Electron"
        case .neutron:  return "Neutron"
        case .proton:   return "Proton"
        }
    }
}

/// A fraction group in an RT Plan.
public struct RTFractionGroup: Sendable, Equatable, Hashable {
    public let fractionGroupID: Int
    public let numberOfFractions: Int
    public let beamDoses: [(beamID: Int, dose: Double)]

    public init(fractionGroupID: Int, numberOfFractions: Int,
                beamDoses: [(beamID: Int, dose: Double)]) {
        self.fractionGroupID = fractionGroupID
        self.numberOfFractions = numberOfFractions
        self.beamDoses = beamDoses
    }

    public static func == (lhs: RTFractionGroup, rhs: RTFractionGroup) -> Bool {
        lhs.fractionGroupID == rhs.fractionGroupID &&
        lhs.numberOfFractions == rhs.numberOfFractions &&
        lhs.beamDoses.map(\.beamID) == rhs.beamDoses.map(\.beamID) &&
        lhs.beamDoses.map(\.dose) == rhs.beamDoses.map(\.dose)
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(fractionGroupID)
        hasher.combine(numberOfFractions)
        hasher.combine(beamDoses.map(\.beamID))
        hasher.combine(beamDoses.map(\.dose))
    }
}

// MARK: - RT Dose

/// A point in a 3D RT dose grid.
public struct RTDosePoint: Sendable, Equatable, Hashable {
    public let x: Double
    public let y: Double
    public let z: Double
    public let dose: Double
    public let units: RTDoseUnits

    public init(x: Double, y: Double, z: Double, dose: Double, units: RTDoseUnits) {
        self.x = x; self.y = y; self.z = z
        self.dose = dose; self.units = units
    }
}

/// Units for RT dose values.
///
/// PS3.3 2026a Dose Units (3004,0002) are GY, RELATIVE and CODED (Table C.8-39); `cgy` is a display
/// convenience with no DICOM term and RELATIVE is absent (P-STUDIO-RT-DOSE-UNITS).
public enum RTDoseUnits: String, Sendable, Equatable, Hashable, CaseIterable {
    case gy  = "GY"
    case cgy = "CGY"

    public var displayName: String {
        switch self {
        case .gy:  return "Gy"
        case .cgy: return "cGy"
        }
    }

    /// Conversion factor to Gy.
    public var conversionToGy: Double {
        switch self {
        case .gy:  return 1.0
        case .cgy: return 0.01
        }
    }
}

/// An isodose level for dose wash display.
public struct RTIsodoseLevel: Sendable, Equatable, Hashable {
    public let percentage: Double
    public let color: RTColor
    public var isVisible: Bool

    public init(percentage: Double, color: RTColor, isVisible: Bool = true) {
        self.percentage = percentage
        self.color = color
        self.isVisible = isVisible
    }
}

/// A single point on a Dose-Volume Histogram curve.
public struct DVHPoint: Sendable, Equatable, Hashable {
    public let dose: Double
    public let volume: Double

    public init(dose: Double, volume: Double) {
        self.dose = dose
        self.volume = volume
    }
}

/// A complete DVH curve for one structure.
public struct DVHCurve: Sendable, Equatable, Hashable {
    public let roiName: String
    public let structureColor: RTColor
    public let points: [DVHPoint]
    public let meanDose: Double?
    public let maxDose: Double?
    public let minDose: Double?

    public init(roiName: String, structureColor: RTColor, points: [DVHPoint],
                meanDose: Double? = nil, maxDose: Double? = nil, minDose: Double? = nil) {
        self.roiName = roiName
        self.structureColor = structureColor
        self.points = points
        self.meanDose = meanDose
        self.maxDose = maxDose
        self.minDose = minDose
    }
}

// MARK: - Segmentation Overlay

/// Display state for a single segmentation overlay.
public struct SegmentOverlay: Sendable, Equatable, Hashable {
    public let segmentNumber: Int
    public let label: String
    public let algorithmType: SegmentAlgorithmType
    public let categoryCode: String?
    public let typeCode: String?
    public let color: RTColor
    public var opacity: Double
    public var isVisible: Bool

    public init(segmentNumber: Int, label: String, algorithmType: SegmentAlgorithmType,
                categoryCode: String? = nil, typeCode: String? = nil,
                color: RTColor, opacity: Double = 0.5, isVisible: Bool = true) {
        self.segmentNumber = segmentNumber
        self.label = label
        self.algorithmType = algorithmType
        self.categoryCode = categoryCode
        self.typeCode = typeCode
        self.color = color
        self.opacity = opacity
        self.isVisible = isVisible
    }
}

/// Algorithm type for segmentation creation.
public enum SegmentAlgorithmType: String, Sendable, Equatable, Hashable, CaseIterable {
    case manual        = "MANUAL"
    case semiautomatic = "SEMIAUTOMATIC"
    case automatic     = "AUTOMATIC"

    public var displayName: String {
        switch self {
        case .manual:        return "Manual"
        case .semiautomatic: return "Semi-automatic"
        case .automatic:     return "Automatic"
        }
    }
}

/// Aggregate state for all segmentation overlays.
public struct SegmentOverlayState: Sendable, Equatable, Hashable {
    public var overlays: [SegmentOverlay]
    public var globalOpacity: Double
    public var showLabels: Bool

    public init(overlays: [SegmentOverlay], globalOpacity: Double = 0.5, showLabels: Bool = true) {
        self.overlays = overlays
        self.globalOpacity = globalOpacity
        self.showLabels = showLabels
    }
}

// MARK: - Parametric Map

/// Type of parametric map.
public enum ParametricMapType: Sendable, Equatable, Hashable {
    case t1Mapping
    case t2Mapping
    case adcMapping
    case perfusion
    case suvMap
    case custom(String)

    public var displayName: String {
        switch self {
        case .t1Mapping:    return "T1 Mapping"
        case .t2Mapping:    return "T2 Mapping"
        case .adcMapping:   return "ADC Mapping"
        case .perfusion:    return "Perfusion"
        case .suvMap:       return "SUV Map"
        case .custom(let s): return "Custom: \(s)"
        }
    }

    /// Physical unit for the map values.
    public var unit: String {
        switch self {
        case .t1Mapping:    return "ms"
        case .t2Mapping:    return "ms"
        case .adcMapping:   return "mm²/s"
        case .perfusion:    return "mL/100g/min"
        case .suvMap:       return "g/mL"
        case .custom:       return ""
        }
    }

    /// Default colormap name for display.
    public var defaultColormapName: String {
        switch self {
        case .t1Mapping:  return "hot"
        case .t2Mapping:  return "hot"
        case .adcMapping: return "viridis"
        case .perfusion:  return "jet"
        case .suvMap:     return "jet"
        case .custom:     return "gray"
        }
    }
}

/// Named colormap for parametric map display.
public enum ColormapName: String, Sendable, Equatable, Hashable, CaseIterable {
    case jet     = "jet"
    case viridis = "viridis"
    case hot     = "hot"
    case cool    = "cool"
    case gray    = "gray"

    public var displayName: String {
        switch self {
        case .jet:     return "Jet"
        case .viridis: return "Viridis"
        case .hot:     return "Hot"
        case .cool:    return "Cool"
        case .gray:    return "Grayscale"
        }
    }

    public var sfSymbol: String {
        switch self {
        case .jet:     return "paintpalette"
        case .viridis: return "waveform"
        case .hot:     return "flame"
        case .cool:    return "snowflake"
        case .gray:    return "circle.lefthalf.filled"
        }
    }
}

/// Display state for a parametric map overlay.
public struct ParametricMapDisplayState: Sendable, Equatable, Hashable {
    public var mapType: ParametricMapType
    public var colormapName: ColormapName
    public var minValue: Double
    public var maxValue: Double
    public var showColorLegend: Bool
    public var overlayOpacity: Double

    public init(mapType: ParametricMapType, colormapName: ColormapName,
                minValue: Double, maxValue: Double,
                showColorLegend: Bool = true, overlayOpacity: Double = 0.8) {
        self.mapType = mapType
        self.colormapName = colormapName
        self.minValue = minValue
        self.maxValue = maxValue
        self.showColorLegend = showColorLegend
        self.overlayOpacity = overlayOpacity
    }
}

/// Input parameters for SUV (Standardized Uptake Value) calculation.
public struct SUVInputParameters: Sendable, Equatable, Hashable {
    public let patientWeightKg: Double
    public let injectedDoseBq: Double
    public let injectionDateTime: Date
    public let decayCorrection: SUVDecayCorrection

    public init(patientWeightKg: Double, injectedDoseBq: Double,
                injectionDateTime: Date, decayCorrection: SUVDecayCorrection = .start) {
        self.patientWeightKg = patientWeightKg
        self.injectedDoseBq = injectedDoseBq
        self.injectionDateTime = injectionDateTime
        self.decayCorrection = decayCorrection
    }
}

/// Decay correction type for SUV calculation.
public enum SUVDecayCorrection: String, Sendable, Equatable, Hashable, CaseIterable {
    case none   = "NONE"
    case start  = "START"
    case admin  = "ADMIN"
    case actual = "ACTUAL"

    public var displayName: String {
        switch self {
        case .none:   return "No Correction"
        case .start:  return "Start of Scan"
        case .admin:  return "Administration"
        case .actual: return "Actual"
        }
    }
}

// MARK: - Waveform Display

/// Display configuration for a single waveform channel.
public struct WaveformDisplayChannel: Sendable, Equatable, Hashable {
    public let channelIndex: Int
    public let label: String
    public let unit: String?
    public var gainMmPerMV: Double
    public var color: RTColor
    public var isVisible: Bool

    public init(channelIndex: Int, label: String, unit: String? = nil,
                gainMmPerMV: Double = 10.0, color: RTColor = .black, isVisible: Bool = true) {
        self.channelIndex = channelIndex
        self.label = label
        self.unit = unit
        self.gainMmPerMV = gainMmPerMV
        self.color = color
        self.isVisible = isVisible
    }
}

/// Standard ECG lead arrangement presets.
public enum ECGLeadArrangement: String, Sendable, Equatable, Hashable, CaseIterable {
    case standard12Lead = "STANDARD_12_LEAD"
    case rhythm         = "RHYTHM"
    case custom         = "CUSTOM"

    public var displayName: String {
        switch self {
        case .standard12Lead: return "Standard 12-Lead"
        case .rhythm:         return "Rhythm Strip"
        case .custom:         return "Custom"
        }
    }
}

/// Global display settings for waveform rendering.
public struct WaveformDisplaySettings: Sendable, Equatable, Hashable {
    public var paperSpeedMmPerSec: Double
    public var gainMmPerMV: Double
    public var showGrid: Bool
    public var leadArrangement: ECGLeadArrangement
    public var timeRangeSeconds: Double

    public init(paperSpeedMmPerSec: Double = 25.0, gainMmPerMV: Double = 10.0,
                showGrid: Bool = true, leadArrangement: ECGLeadArrangement = .standard12Lead,
                timeRangeSeconds: Double = 10.0) {
        self.paperSpeedMmPerSec = paperSpeedMmPerSec
        self.gainMmPerMV = gainMmPerMV
        self.showGrid = showGrid
        self.leadArrangement = leadArrangement
        self.timeRangeSeconds = timeRangeSeconds
    }
}

/// A caliper measurement placed on a waveform.
public struct WaveformCaliperMeasurement: Sendable, Equatable, Hashable {
    public let startSampleIndex: Int
    public let endSampleIndex: Int
    public let samplingFrequency: Double
    public let label: String?

    public init(startSampleIndex: Int, endSampleIndex: Int,
                samplingFrequency: Double, label: String? = nil) {
        self.startSampleIndex = startSampleIndex
        self.endSampleIndex = endSampleIndex
        self.samplingFrequency = samplingFrequency
        self.label = label
    }

    /// Duration of the caliper span in milliseconds.
    public var durationMs: Double {
        let samples = Double(abs(endSampleIndex - startSampleIndex))
        guard samplingFrequency > 0 else { return 0 }
        return (samples / samplingFrequency) * 1000.0
    }

    /// Heart rate in beats per minute derived from the RR interval, or nil if duration is zero.
    public var bpm: Double? {
        guard durationMs > 0 else { return nil }
        return 60000.0 / durationMs
    }
}

// MARK: - Video Display

/// Playback state for a video DICOM object.
public struct VideoDisplayState: Sendable, Equatable, Hashable {
    public var isPlaying: Bool
    public var currentFrameIndex: Int
    public var playbackSpeed: Double
    public let totalFrames: Int
    public let frameRate: Double

    public init(isPlaying: Bool = false, currentFrameIndex: Int = 0,
                playbackSpeed: Double = 1.0, totalFrames: Int, frameRate: Double) {
        self.isPlaying = isPlaying
        self.currentFrameIndex = currentFrameIndex
        self.playbackSpeed = playbackSpeed
        self.totalFrames = totalFrames
        self.frameRate = frameRate
    }

    /// Current playback position in seconds.
    public var currentTimeSeconds: Double {
        guard frameRate > 0 else { return 0 }
        return Double(currentFrameIndex) / frameRate
    }

    /// Total video duration in seconds.
    public var totalDurationSeconds: Double {
        guard frameRate > 0 else { return 0 }
        return Double(totalFrames) / frameRate
    }
}

/// Preset playback speeds for video.
public enum VideoPlaybackSpeed: String, Sendable, Equatable, Hashable, CaseIterable {
    case half       = "0.5x"
    case normal     = "1.0x"
    case double     = "2.0x"
    case quadruple  = "4.0x"

    public var displayName: String {
        switch self {
        case .half:      return "0.5×"
        case .normal:    return "1×"
        case .double:    return "2×"
        case .quadruple: return "4×"
        }
    }

    public var speedMultiplier: Double {
        switch self {
        case .half:      return 0.5
        case .normal:    return 1.0
        case .double:    return 2.0
        case .quadruple: return 4.0
        }
    }
}

// MARK: - Encapsulated Document

/// Type of encapsulated document.
public enum EncapsulatedDocumentType: String, Sendable, Equatable, Hashable, CaseIterable {
    case pdf     = "PDF"
    case cda     = "CDA"
    case stl     = "STL"
    case obj     = "OBJ"
    case mtl     = "MTL"
    case unknown = "UNKNOWN"

    public var displayName: String {
        switch self {
        case .pdf:     return "PDF Document"
        case .cda:     return "Clinical Document"
        case .stl:     return "STL 3D Model"
        case .obj:     return "OBJ 3D Model"
        case .mtl:     return "MTL Material"
        case .unknown: return "Unknown Document"
        }
    }

    public var mimeType: String {
        switch self {
        case .pdf:     return "application/pdf"
        case .cda:     return "text/XML"   // PS3.3 A.45.2.4: Enumerated Value for MIME Type of Encapsulated Document (0042,0012)
        case .stl:     return "model/stl"
        case .obj:     return "model/obj"
        case .mtl:     return "model/mtl"
        case .unknown: return "application/octet-stream"
        }
    }

    public var sfSymbol: String {
        switch self {
        case .pdf:     return "doc.fill"
        case .cda:     return "doc.text"
        case .stl:     return "cube"
        case .obj:     return "cube.transparent"
        case .mtl:     return "paintbrush"
        case .unknown: return "doc.questionmark"
        }
    }

    public var isViewable: Bool {
        switch self {
        case .pdf, .cda, .stl, .obj: return true
        case .mtl, .unknown:         return false
        }
    }

    public var is3DModel: Bool {
        switch self {
        case .stl, .obj: return true
        default:         return false
        }
    }
}

/// Display state for an encapsulated document.
public struct EncapsulatedDocumentDisplayState: Sendable, Equatable, Hashable {
    public let documentType: EncapsulatedDocumentType
    public var isLoaded: Bool
    public var pageCount: Int
    public var currentPage: Int
    public var zoom: Double
    public let title: String?

    public init(documentType: EncapsulatedDocumentType, isLoaded: Bool = false,
                pageCount: Int = 0, currentPage: Int = 0,
                zoom: Double = 1.0, title: String? = nil) {
        self.documentType = documentType
        self.isLoaded = isLoaded
        self.pageCount = pageCount
        self.currentPage = currentPage
        self.zoom = zoom
        self.title = title
    }
}

// MARK: - Secondary Capture

/// Display information for a Secondary Capture image.
public struct SecondaryCaptureDisplayInfo: Sendable, Equatable, Hashable {
    public let captureType: SecondaryCaptureDisplayType
    public let deviceDescription: String?
    public let captureDate: String?
    public let numberOfFrames: Int

    public init(captureType: SecondaryCaptureDisplayType, deviceDescription: String? = nil,
                captureDate: String? = nil, numberOfFrames: Int = 1) {
        self.captureType = captureType
        self.deviceDescription = deviceDescription
        self.captureDate = captureDate
        self.numberOfFrames = numberOfFrames
    }
}

/// Secondary Capture SOP Class types.
public enum SecondaryCaptureDisplayType: String, Sendable, Equatable, Hashable, CaseIterable {
    case singleFrame                = "SINGLE_FRAME"
    case multiFrameSingleBit        = "MULTI_FRAME_SINGLE_BIT"
    case multiFrameGrayscaleByte    = "MULTI_FRAME_GRAYSCALE_BYTE"
    case multiFrameGrayscaleWord    = "MULTI_FRAME_GRAYSCALE_WORD"
    case multiFrameTrueColor        = "MULTI_FRAME_TRUE_COLOR"

    public var displayName: String {
        switch self {
        case .singleFrame:             return "Single Frame SC"
        case .multiFrameSingleBit:     return "Multi-Frame Single Bit"
        case .multiFrameGrayscaleByte: return "Multi-Frame Grayscale (8-bit)"
        case .multiFrameGrayscaleWord: return "Multi-Frame Grayscale (16-bit)"
        case .multiFrameTrueColor:     return "Multi-Frame True Color"
        }
    }

    /// SOP Class UID for this Secondary Capture type.
    public var sopClassUID: String {
        switch self {
        case .singleFrame:             return "1.2.840.10008.5.1.4.1.1.7"
        case .multiFrameSingleBit:     return "1.2.840.10008.5.1.4.1.1.7.1"
        case .multiFrameGrayscaleByte: return "1.2.840.10008.5.1.4.1.1.7.2"
        case .multiFrameGrayscaleWord: return "1.2.840.10008.5.1.4.1.1.7.3"
        case .multiFrameTrueColor:     return "1.2.840.10008.5.1.4.1.1.7.4"
        }
    }
}

// MARK: - Whole Slide Imaging

/// An optical path (fluorescence channel or brightfield illumination) in a WSI image.
public struct WSIOpticalPath: Sendable, Equatable, Hashable {
    public let opticalPathID: String
    public let description: String?
    public let illuminationColor: RTColor
    public var isVisible: Bool

    public init(opticalPathID: String, description: String? = nil,
                illuminationColor: RTColor, isVisible: Bool = true) {
        self.opticalPathID = opticalPathID
        self.description = description
        self.illuminationColor = illuminationColor
        self.isVisible = isVisible
    }
}

/// A single resolution level in a WSI pyramid.
public struct WSITileLevel: Sendable, Equatable, Hashable {
    public let level: Int
    public let width: Int
    public let height: Int
    public let tileWidth: Int
    public let tileHeight: Int

    public init(level: Int, width: Int, height: Int, tileWidth: Int, tileHeight: Int) {
        self.level = level
        self.width = width
        self.height = height
        self.tileWidth = tileWidth
        self.tileHeight = tileHeight
    }

    /// Number of tiles in the X direction for this level.
    public var tileCountX: Int { (width + tileWidth - 1) / tileWidth }
    /// Number of tiles in the Y direction for this level.
    public var tileCountY: Int { (height + tileHeight - 1) / tileHeight }
}

/// Viewport and zoom state for WSI display.
public struct WSIDisplayState: Sendable, Equatable, Hashable {
    public var currentLevel: Int
    public var zoomFactor: Double
    public var viewportX: Double
    public var viewportY: Double
    public var visibleOpticalPaths: [String]
    public var showAnnotations: Bool

    public init(currentLevel: Int = 0, zoomFactor: Double = 1.0,
                viewportX: Double = 0, viewportY: Double = 0,
                visibleOpticalPaths: [String], showAnnotations: Bool = true) {
        self.currentLevel = currentLevel
        self.zoomFactor = zoomFactor
        self.viewportX = viewportX
        self.viewportY = viewportY
        self.visibleOpticalPaths = visibleOpticalPaths
        self.showAnnotations = showAnnotations
    }
}
