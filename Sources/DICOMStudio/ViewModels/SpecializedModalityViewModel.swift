// SpecializedModalityViewModel.swift
// DICOMStudio
//
// DICOM Studio — ViewModel for Specialized Modality Support
// NEMA-verified: 2026a, checked 2026-10-05 — carries no DICOM-standard data beyond the ECG channel unit "mV" (a UCUM code; PS3.3 2026a C.10.9 Channel Sensitivity Units Sequence carries UCUM codes) and tab names; display state over SpecializedModalityService

import Foundation
import Observation
import DICOMKit

// MARK: - Tab Enum

/// Navigation tabs for specialized modality views.
public enum SpecializedModalityTab: String, Sendable, Equatable, Hashable, CaseIterable {
    case rtStructureSet      = "RT_STRUCTURE_SET"
    case rtPlan              = "RT_PLAN"
    case rtDose              = "RT_DOSE"
    case segmentation        = "SEGMENTATION"
    case parametricMap       = "PARAMETRIC_MAP"
    case waveform            = "WAVEFORM"
    case video               = "VIDEO"
    case encapsulatedDocument = "ENCAPSULATED_DOCUMENT"
    case secondaryCapture    = "SECONDARY_CAPTURE"
    case wholeSlideImaging   = "WHOLE_SLIDE_IMAGING"

    public var displayName: String {
        switch self {
        case .rtStructureSet:       return "RT Structure Set"
        case .rtPlan:               return "RT Plan"
        case .rtDose:               return "RT Dose"
        case .segmentation:         return "Segmentation"
        case .parametricMap:        return "Parametric Map"
        case .waveform:             return "Waveform"
        case .video:                return "Video"
        case .encapsulatedDocument: return "Encapsulated Document"
        case .secondaryCapture:     return "Secondary Capture"
        case .wholeSlideImaging:    return "Whole Slide Imaging"
        }
    }

    public var sfSymbol: String {
        switch self {
        case .rtStructureSet:       return "circle.dashed"
        case .rtPlan:               return "list.bullet.clipboard"
        case .rtDose:               return "waveform.path.ecg.rectangle"
        case .segmentation:         return "rectangle.3.group"
        case .parametricMap:        return "paintpalette"
        case .waveform:             return "waveform.ecg"
        case .video:                return "play.rectangle"
        case .encapsulatedDocument: return "doc.fill"
        case .secondaryCapture:     return "camera"
        case .wholeSlideImaging:    return "magnifyingglass"
        }
    }
}

// MARK: - ViewModel

/// ViewModel for specialized modality support, managing RT, segmentation, parametric maps,
/// waveforms, video, encapsulated documents, secondary capture, and WSI display state.
///
/// Requires macOS 14+ / iOS 17+ for the `@Observable` macro.
@available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
@Observable
public final class SpecializedModalityViewModel {

    // MARK: - Navigation

    public var activeModality: SpecializedModalityTab = .rtStructureSet
    public var isLoading: Bool = false
    public var errorMessage: String? = nil

    // MARK: - RT Properties

    public var rois: [RTStructureSetROI] = []
    public var selectedROIID: Int? = nil
    public var isodoseLevels: [RTIsodoseLevel] = []
    public var dvhCurves: [DVHCurve] = []
    public var beams: [RTBeam] = []
    public var fractionGroups: [RTFractionGroup] = []

    // MARK: - Segmentation Properties

    public var segmentOverlayState: SegmentOverlayState = .init(overlays: [])
    public var showSegmentLabels: Bool = true

    // MARK: - Parametric Map Properties

    public var parametricMapDisplayState: ParametricMapDisplayState = .init(
        mapType: .t1Mapping, colormapName: .hot, minValue: 0, maxValue: 3000)
    public var suvParameters: SUVInputParameters? = nil
    public var showColorLegend: Bool = true

    // MARK: - Waveform Properties

    public var waveformSettings: WaveformDisplaySettings = .init()
    public var waveformChannels: [WaveformDisplayChannel] = []
    public var caliperMeasurements: [WaveformCaliperMeasurement] = []
    public var selectedWaveformSopClass: String = Waveform.twelveLeadECGStorageUID

    // MARK: - Video Properties

    public var videoDisplayState: VideoDisplayState? = nil
    public var isVideoPlaying: Bool = false

    // MARK: - Document Properties

    public var documentDisplayState: EncapsulatedDocumentDisplayState? = nil

    // MARK: - WSI Properties

    public var wsiDisplayState: WSIDisplayState = .init(visibleOpticalPaths: [])
    public var wsiTileLevels: [WSITileLevel] = []
    public var wsiOpticalPaths: [WSIOpticalPath] = []

    // MARK: - Service

    private let service: SpecializedModalityService

    public init(service: SpecializedModalityService = SpecializedModalityService()) {
        self.service = service
    }

    // MARK: - RT Methods

    /// Loads four representative sample ROIs (GTV, CTV, PTV, Spinal Cord OAR).
    public func loadDefaultROIs() {
        let samples: [RTStructureSetROI] = [
            RTStructureSetROI(id: 1, name: "GTV", roiType: .gtv,
                              color: RTHelpers.colorForROIType(.gtv)),
            RTStructureSetROI(id: 2, name: "CTV", roiType: .ctv,
                              color: RTHelpers.colorForROIType(.ctv)),
            RTStructureSetROI(id: 3, name: "PTV", roiType: .ptv,
                              color: RTHelpers.colorForROIType(.ptv)),
            RTStructureSetROI(id: 4, name: "Spinal Cord", roiType: .oar,
                              color: RTHelpers.colorForROIType(.oar)),
        ]
        service.setROIs(samples)
        rois = service.getROIs()
    }

    /// Toggles the visibility of the ROI with the given ID.
    public func toggleROIVisibility(roiID: Int) {
        let current = service.getROIs().first(where: { $0.id == roiID })?.isVisible ?? true
        service.setROIVisibility(roiID: roiID, visible: !current)
        rois = service.getROIs()
    }

    // MARK: - Segmentation Methods

    /// Loads `count` default segment overlays using `SegmentationHelpers`.
    public func loadDefaultSegments(count: Int = 3) {
        let overlays = SegmentationHelpers.buildOverlays(segmentCount: count)
        let state = SegmentOverlayState(overlays: overlays)
        service.updateSegmentOverlayState(state)
        segmentOverlayState = service.getSegmentOverlayState()
    }

    /// Toggles the visibility of a segment overlay by segment number.
    public func toggleSegmentVisibility(segmentNumber: Int) {
        service.setSegmentVisibility(segmentNumber: segmentNumber,
                                     visible: !isSegmentVisible(segmentNumber))
        segmentOverlayState = service.getSegmentOverlayState()
    }

    /// Sets the global opacity for all segment overlays.
    public func setGlobalSegmentOpacity(_ opacity: Double) {
        service.setGlobalOpacity(opacity)
        segmentOverlayState = service.getSegmentOverlayState()
    }

    // MARK: - Parametric Map Methods

    /// Applies a new colormap to the current parametric map display state.
    public func applyColormap(_ colormap: ColormapName) {
        let current = service.getParametricMapDisplayState()
        let updated = ParametricMapDisplayState(
            mapType: current.mapType, colormapName: colormap,
            minValue: current.minValue, maxValue: current.maxValue,
            showColorLegend: current.showColorLegend, overlayOpacity: current.overlayOpacity)
        service.updateParametricMapDisplayState(updated)
        parametricMapDisplayState = service.getParametricMapDisplayState()
    }

    // MARK: - Waveform Methods

    /// Loads waveform channels from standard labels for the given SOP Class UID.
    public func loadDefaultWaveformChannels(sopClassUID: String) {
        let labels: [String]
        if sopClassUID.contains("9.1") {
            labels = WaveformHelpers.standardECGLeadLabels()
        } else if sopClassUID.contains("9.2") {
            labels = WaveformHelpers.hemodynamicChannelLabels()
        } else {
            labels = WaveformHelpers.standardECGLeadLabels()
        }
        let channels = labels.enumerated().map { (i, label) in
            WaveformDisplayChannel(channelIndex: i, label: label, unit: "mV")
        }
        service.setWaveformChannels(channels)
        waveformChannels = service.getWaveformChannels()
    }

    /// Adds a caliper measurement to the waveform.
    public func addCaliperMeasurement(_ m: WaveformCaliperMeasurement) {
        service.addCaliperMeasurement(m)
        caliperMeasurements = service.getCaliperMeasurements()
    }

    /// Removes all caliper measurements.
    public func clearCaliperMeasurements() {
        service.clearCaliperMeasurements()
        caliperMeasurements = []
    }

    // MARK: - Video Methods

    /// Creates a sample video display state with the given frame count and rate.
    public func loadSampleVideo(totalFrames: Int = 120, frameRate: Double = 25.0) {
        let state = VideoDisplayState(totalFrames: totalFrames, frameRate: frameRate)
        service.setVideoDisplayState(state)
        videoDisplayState = service.getVideoDisplayState()
        isVideoPlaying = false
    }

    /// Toggles video playback on/off.
    public func toggleVideoPlayback() {
        let playing = !(videoDisplayState?.isPlaying ?? false)
        service.updatePlaybackState(isPlaying: playing)
        videoDisplayState = service.getVideoDisplayState()
        isVideoPlaying = playing
    }

    /// Advances the video by one frame and syncs local state.
    public func advanceVideoFrame() {
        service.advanceFrame()
        videoDisplayState = service.getVideoDisplayState()
    }

    // MARK: - Document Methods

    /// Creates a display state for an encapsulated document of the given type.
    public func loadDocument(type: EncapsulatedDocumentType, title: String?) {
        let state = EncapsulatedDocumentDisplayState(
            documentType: type, isLoaded: true, pageCount: 10,
            currentPage: 0, zoom: EncapsulatedDocumentHelpers.defaultZoom(for: type),
            title: title)
        service.setDocumentDisplayState(state)
        documentDisplayState = service.getDocumentDisplayState()
    }

    /// Navigates to the next page of the encapsulated document.
    public func nextDocumentPage() {
        service.nextPage()
        documentDisplayState = service.getDocumentDisplayState()
    }

    /// Navigates to the previous page of the encapsulated document.
    public func previousDocumentPage() {
        service.previousPage()
        documentDisplayState = service.getDocumentDisplayState()
    }

    // MARK: - WSI Methods

    /// Loads five sample WSI pyramid levels (40× down to 2.5×, 256×256 tiles).
    public func loadWSILevels() {
        let levels: [WSITileLevel] = [
            WSITileLevel(level: 0, width: 8192, height: 8192, tileWidth: 256, tileHeight: 256),
            WSITileLevel(level: 1, width: 4096, height: 4096, tileWidth: 256, tileHeight: 256),
            WSITileLevel(level: 2, width: 2048, height: 2048, tileWidth: 256, tileHeight: 256),
            WSITileLevel(level: 3, width: 1024, height: 1024, tileWidth: 256, tileHeight: 256),
            WSITileLevel(level: 4, width:  512, height:  512, tileWidth: 256, tileHeight: 256),
        ]
        service.setTileLevels(levels)
        wsiTileLevels = service.getTileLevels()
    }

    /// Updates the WSI viewport zoom factor.
    public func zoomWSI(to zoomFactor: Double) {
        var state = service.getWSIDisplayState()
        state = WSIDisplayState(
            currentLevel: state.currentLevel, zoomFactor: zoomFactor,
            viewportX: state.viewportX, viewportY: state.viewportY,
            visibleOpticalPaths: state.visibleOpticalPaths,
            showAnnotations: state.showAnnotations)
        service.updateWSIDisplayState(state)
        wsiDisplayState = service.getWSIDisplayState()
    }

    // MARK: - Reset

    /// Resets all state to defaults.
    public func resetAll() {
        service.resetAll()
        rois = []
        selectedROIID = nil
        isodoseLevels = []
        dvhCurves = []
        beams = []
        fractionGroups = []
        segmentOverlayState = SegmentOverlayState(overlays: [])
        parametricMapDisplayState = ParametricMapDisplayState(
            mapType: .t1Mapping, colormapName: .hot, minValue: 0, maxValue: 3000)
        suvParameters = nil
        waveformSettings = WaveformDisplaySettings()
        waveformChannels = []
        caliperMeasurements = []
        videoDisplayState = nil
        isVideoPlaying = false
        documentDisplayState = nil
        wsiDisplayState = WSIDisplayState(visibleOpticalPaths: [])
        wsiTileLevels = []
        wsiOpticalPaths = []
    }

    // MARK: - Private Helpers

    private func isSegmentVisible(_ segmentNumber: Int) -> Bool {
        segmentOverlayState.overlays.first(where: { $0.segmentNumber == segmentNumber })?.isVisible ?? true
    }
}
