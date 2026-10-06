// SpecializedModalityModelTests.swift
// DICOMStudioTests

import Testing
@testable import DICOMStudio
import Foundation

@Suite("Specialized Modality Model Tests")
struct SpecializedModalityModelTests {

    // MARK: - RTROIType

    @Test("RTROIType all cases have raw values")
    func testRTROITypeRawValues() {
        for roiType in RTROIType.allCases {
            #expect(!roiType.rawValue.isEmpty)
        }
    }

    @Test("RTROIType all cases have non-empty display names")
    func testRTROITypeDisplayNames() {
        for roiType in RTROIType.allCases {
            #expect(!roiType.displayName.isEmpty)
        }
    }

    @Test("RTROIType all cases have non-empty SF symbols")
    func testRTROITypeSFSymbols() {
        for roiType in RTROIType.allCases {
            #expect(!roiType.sfSymbol.isEmpty)
        }
    }

    @Test("RTROIType carries the 25 RT ROI Interpreted Type Defined Terms")
    func testRTROITypeCaseCount() {
        // PS3.3 2026a C.8.8.8.1 (Table C.8-44 RT ROI Interpreted Type (3006,00A4)), in order
        let terms = ["EXTERNAL", "PTV", "CTV", "GTV", "TREATED_VOLUME", "IRRAD_VOLUME", "OAR", "BOLUS",
                     "AVOIDANCE", "ORGAN", "MARKER", "REGISTRATION", "ISOCENTER", "CONTRAST_AGENT", "CAVITY",
                     "BRACHY_CHANNEL", "BRACHY_ACCESSORY", "BRACHY_SRC_APP", "BRACHY_CHNL_SHLD", "SUPPORT",
                     "FIXATION", "DOSE_REGION", "CONTROL", "DOSE_MEASUREMENT", "DEVICE"]
        #expect(RTROIType.allCases.count == 25)
        #expect(RTROIType.allCases.map(\.rawValue) == terms)
        for term in terms {
            #expect(RTROIType(rawValue: term)?.rawValue == term)
        }
        #expect(RTROIType(rawValue: "BRACHY_SRC_APP") == .brachySourceApplicator)
        #expect(RTROIType.gtv.displayName == "Gross Tumor Volume")
    }

    @Test("RTROIType maps OTHER, unknown and empty values to nil")
    func testRTROITypeUnknownIsNil() {
        #expect(RTROIType(rawValue: "OTHER") == nil)
        #expect(RTROIType(rawValue: "NOT_A_TERM") == nil)
        #expect(RTROIType(rawValue: "") == nil)
        #expect(RTROIType(rawValue: "ptv") == nil)
    }

    @Test("RTROIType PTV raw value is PTV")
    func testRTROITypePTVRawValue() {
        #expect(RTROIType.ptv.rawValue == "PTV")
    }

    @Test("RTROIType OAR raw value is OAR")
    func testRTROITypeOARRawValue() {
        #expect(RTROIType.oar.rawValue == "OAR")
    }

    // MARK: - RTColor

    @Test("RTColor red preset has red=1.0")
    func testRTColorRedPreset() {
        #expect(RTColor.red.red == 1.0)
        #expect(RTColor.red.green == 0.0)
        #expect(RTColor.red.blue == 0.0)
        #expect(RTColor.red.alpha == 1.0)
    }

    @Test("RTColor black preset is all zeros")
    func testRTColorBlackPreset() {
        #expect(RTColor.black.red == 0.0)
        #expect(RTColor.black.green == 0.0)
        #expect(RTColor.black.blue == 0.0)
    }

    @Test("RTColor white preset is all ones")
    func testRTColorWhitePreset() {
        #expect(RTColor.white.red == 1.0)
        #expect(RTColor.white.green == 1.0)
        #expect(RTColor.white.blue == 1.0)
    }

    @Test("RTColor default alpha is 1.0")
    func testRTColorDefaultAlpha() {
        let color = RTColor(red: 0.5, green: 0.5, blue: 0.5)
        #expect(color.alpha == 1.0)
    }

    @Test("RTColor static presets exist for all standard colors")
    func testRTColorStaticPresets() {
        _ = RTColor.red
        _ = RTColor.green
        _ = RTColor.blue
        _ = RTColor.yellow
        _ = RTColor.orange
        _ = RTColor.pink
        _ = RTColor.purple
        _ = RTColor.cyan
        _ = RTColor.white
        _ = RTColor.black
    }

    // MARK: - RTDoseUnits

    @Test("RTDoseUnits Gy conversion is 1.0")
    func testRTDoseUnitsGy() {
        #expect(RTDoseUnits.gy.conversionToGy == 1.0)
    }

    @Test("RTDoseUnits cGy conversion is 0.01")
    func testRTDoseUnitsCGy() {
        #expect(RTDoseUnits.cgy.conversionToGy == 0.01)
    }

    @Test("RTDoseUnits display names are non-empty")
    func testRTDoseUnitsDisplayNames() {
        #expect(!RTDoseUnits.gy.displayName.isEmpty)
        #expect(!RTDoseUnits.cgy.displayName.isEmpty)
    }

    // MARK: - DVHCurve

    @Test("DVHCurve initialises with provided values")
    func testDVHCurveInit() {
        let points = [DVHPoint(dose: 0, volume: 100), DVHPoint(dose: 60, volume: 50)]
        let curve = DVHCurve(roiName: "PTV", structureColor: .red, points: points,
                             meanDose: 45.0, maxDose: 60.0, minDose: 0.0)
        #expect(curve.roiName == "PTV")
        #expect(curve.points.count == 2)
        #expect(curve.meanDose == 45.0)
    }

    @Test("DVHPoint stores dose and volume")
    func testDVHPoint() {
        let p = DVHPoint(dose: 50.0, volume: 95.0)
        #expect(p.dose == 50.0)
        #expect(p.volume == 95.0)
    }

    // MARK: - SegmentAlgorithmType

    @Test("SegmentAlgorithmType all cases have display names")
    func testSegmentAlgorithmTypeDisplayNames() {
        for type in SegmentAlgorithmType.allCases {
            #expect(!type.displayName.isEmpty)
        }
    }

    @Test("SegmentAlgorithmType manual raw value")
    func testSegmentAlgorithmTypeManual() {
        #expect(SegmentAlgorithmType.manual.rawValue == "MANUAL")
    }

    // MARK: - ParametricMapType

    @Test("ParametricMapType known cases have non-empty display names")
    func testParametricMapTypeDisplayNames() {
        #expect(!ParametricMapType.t1Mapping.displayName.isEmpty)
        #expect(!ParametricMapType.t2Mapping.displayName.isEmpty)
        #expect(!ParametricMapType.adcMapping.displayName.isEmpty)
        #expect(!ParametricMapType.perfusion.displayName.isEmpty)
        #expect(!ParametricMapType.suvMap.displayName.isEmpty)
    }

    @Test("ParametricMapType known cases have non-empty units")
    func testParametricMapTypeUnits() {
        #expect(!ParametricMapType.t1Mapping.unit.isEmpty)
        #expect(!ParametricMapType.adcMapping.unit.isEmpty)
        #expect(!ParametricMapType.suvMap.unit.isEmpty)
    }

    @Test("ParametricMapType known cases have default colormap names")
    func testParametricMapTypeDefaultColormap() {
        #expect(!ParametricMapType.t1Mapping.defaultColormapName.isEmpty)
        #expect(!ParametricMapType.adcMapping.defaultColormapName.isEmpty)
    }

    @Test("ParametricMapType custom case includes associated string in displayName")
    func testParametricMapTypeCustom() {
        let type = ParametricMapType.custom("MyMap")
        #expect(type.displayName.contains("MyMap"))
    }

    // MARK: - ColormapName

    @Test("ColormapName all cases have non-empty display names")
    func testColormapNameDisplayNames() {
        for name in ColormapName.allCases {
            #expect(!name.displayName.isEmpty)
        }
    }

    @Test("ColormapName all cases have non-empty SF symbols")
    func testColormapNameSFSymbols() {
        for name in ColormapName.allCases {
            #expect(!name.sfSymbol.isEmpty)
        }
    }

    // MARK: - VideoPlaybackSpeed

    @Test("VideoPlaybackSpeed normal multiplier is 1.0")
    func testVideoPlaybackSpeedNormal() {
        #expect(VideoPlaybackSpeed.normal.speedMultiplier == 1.0)
    }

    @Test("VideoPlaybackSpeed half multiplier is 0.5")
    func testVideoPlaybackSpeedHalf() {
        #expect(VideoPlaybackSpeed.half.speedMultiplier == 0.5)
    }

    @Test("VideoPlaybackSpeed double multiplier is 2.0")
    func testVideoPlaybackSpeedDouble() {
        #expect(VideoPlaybackSpeed.double.speedMultiplier == 2.0)
    }

    @Test("VideoPlaybackSpeed quadruple multiplier is 4.0")
    func testVideoPlaybackSpeedQuadruple() {
        #expect(VideoPlaybackSpeed.quadruple.speedMultiplier == 4.0)
    }

    // MARK: - EncapsulatedDocumentType

    @Test("EncapsulatedDocumentType PDF is viewable")
    func testEncapsulatedDocumentTypePDFViewable() {
        #expect(EncapsulatedDocumentType.pdf.isViewable)
    }

    @Test("EncapsulatedDocumentType STL is a 3D model")
    func testEncapsulatedDocumentTypeSTL3DModel() {
        #expect(EncapsulatedDocumentType.stl.is3DModel)
    }

    @Test("EncapsulatedDocumentType unknown is not viewable")
    func testEncapsulatedDocumentTypeUnknownNotViewable() {
        #expect(!EncapsulatedDocumentType.unknown.isViewable)
    }

    @Test("EncapsulatedDocumentType PDF has correct MIME type")
    func testEncapsulatedDocumentTypePDFMimeType() {
        #expect(EncapsulatedDocumentType.pdf.mimeType == "application/pdf")
    }

    @Test("EncapsulatedDocumentType all cases have non-empty SF symbols")
    func testEncapsulatedDocumentTypeSFSymbols() {
        for type in EncapsulatedDocumentType.allCases {
            #expect(!type.sfSymbol.isEmpty)
        }
    }

    // MARK: - SecondaryCaptureDisplayType

    @Test("SecondaryCaptureDisplayType all cases have non-empty SOP Class UIDs")
    func testSecondaryCaptureDisplayTypeSopClassUIDs() {
        for type in SecondaryCaptureDisplayType.allCases {
            #expect(!type.sopClassUID.isEmpty)
        }
    }

    @Test("SecondaryCaptureDisplayType single frame SOP Class UID")
    func testSecondaryCaptureDisplayTypeSingleFrame() {
        #expect(SecondaryCaptureDisplayType.singleFrame.sopClassUID == "1.2.840.10008.5.1.4.1.1.7")
    }

    // MARK: - WaveformCaliperMeasurement

    @Test("WaveformCaliperMeasurement durationMs calculates correctly")
    func testWaveformCaliperMeasurementDurationMs() {
        // 250 samples at 250 Hz = 1 second = 1000 ms
        let caliper = WaveformCaliperMeasurement(startSampleIndex: 0, endSampleIndex: 250,
                                                  samplingFrequency: 250.0)
        #expect(abs(caliper.durationMs - 1000.0) < 0.001)
    }

    @Test("WaveformCaliperMeasurement bpm calculates correctly")
    func testWaveformCaliperMeasurementBPM() {
        // 600 ms RR interval → 100 bpm
        let caliper = WaveformCaliperMeasurement(startSampleIndex: 0, endSampleIndex: 150,
                                                  samplingFrequency: 250.0)
        if let bpm = caliper.bpm {
            #expect(abs(bpm - 100.0) < 0.1)
        } else {
            Issue.record("Expected bpm to be non-nil")
        }
    }

    @Test("WaveformCaliperMeasurement bpm is nil when duration is zero")
    func testWaveformCaliperMeasurementBPMNilWhenZero() {
        let caliper = WaveformCaliperMeasurement(startSampleIndex: 5, endSampleIndex: 5,
                                                  samplingFrequency: 250.0)
        #expect(caliper.bpm == nil)
    }

    // MARK: - VideoDisplayState

    @Test("VideoDisplayState currentTimeSeconds computed correctly")
    func testVideoDisplayStateCurrentTime() {
        let state = VideoDisplayState(currentFrameIndex: 25, totalFrames: 100, frameRate: 25.0)
        #expect(abs(state.currentTimeSeconds - 1.0) < 0.001)
    }

    @Test("VideoDisplayState totalDurationSeconds computed correctly")
    func testVideoDisplayStateTotalDuration() {
        let state = VideoDisplayState(totalFrames: 250, frameRate: 25.0)
        #expect(abs(state.totalDurationSeconds - 10.0) < 0.001)
    }

    // MARK: - WSITileLevel

    @Test("WSITileLevel tileCountX computed correctly")
    func testWSITileLevelTileCountX() {
        let level = WSITileLevel(level: 0, width: 512, height: 512, tileWidth: 256, tileHeight: 256)
        #expect(level.tileCountX == 2)
    }

    @Test("WSITileLevel tileCountY computed correctly")
    func testWSITileLevelTileCountY() {
        let level = WSITileLevel(level: 0, width: 512, height: 512, tileWidth: 256, tileHeight: 256)
        #expect(level.tileCountY == 2)
    }

    @Test("WSITileLevel tileCount rounds up for non-divisible dimensions")
    func testWSITileLevelTileCountRoundsUp() {
        let level = WSITileLevel(level: 0, width: 513, height: 513, tileWidth: 256, tileHeight: 256)
        #expect(level.tileCountX == 3)
        #expect(level.tileCountY == 3)
    }
}
