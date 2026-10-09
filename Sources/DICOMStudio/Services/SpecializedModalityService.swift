// SpecializedModalityService.swift
// DICOMStudio
//
// DICOM Studio — Service for Specialized Modality state management
// NEMA-verified: 2026a, checked 2026-10-05 — carries no DICOM-standard data (thread-safe display state over the SpecializedModalityModel types verified there)

import Foundation

/// Thread-safe service managing display state for RT, Segmentation, Parametric Maps,
/// Waveforms, Video, Encapsulated Documents, and Whole Slide Imaging.
public final class SpecializedModalityService: @unchecked Sendable {

    // MARK: - Lock

    private let lock = NSLock()

    // MARK: - RT State

    private var _rois: [RTStructureSetROI] = []
    private var _selectedROIID: Int? = nil
    private var _isodoseLevels: [RTIsodoseLevel] = []
    private var _dvhCurves: [DVHCurve] = []
    private var _beams: [RTBeam] = []
    private var _fractionGroups: [RTFractionGroup] = []

    // MARK: - Segmentation State

    private var _segmentOverlayState: SegmentOverlayState

    // MARK: - Parametric Map State

    private var _parametricMapDisplayState: ParametricMapDisplayState
    private var _suvParameters: SUVInputParameters? = nil

    // MARK: - Waveform State

    private var _waveformSettings: WaveformDisplaySettings
    private var _waveformChannels: [WaveformDisplayChannel] = []
    private var _caliperMeasurements: [WaveformCaliperMeasurement] = []

    // MARK: - Video State

    private var _videoDisplayState: VideoDisplayState? = nil

    // MARK: - Encapsulated Document State

    private var _documentDisplayState: EncapsulatedDocumentDisplayState? = nil

    // MARK: - WSI State

    private var _wsiDisplayState: WSIDisplayState
    private var _tileLevels: [WSITileLevel] = []
    private var _opticalPaths: [WSIOpticalPath] = []

    // MARK: - Init

    public init() {
        _segmentOverlayState = SegmentOverlayState(overlays: [])
        _parametricMapDisplayState = ParametricMapDisplayState(
            mapType: .t1Mapping, colormapName: .hot, minValue: 0, maxValue: 3000)
        _waveformSettings = WaveformDisplaySettings()
        _wsiDisplayState = WSIDisplayState(visibleOpticalPaths: [])
    }

    // MARK: - RT Methods

    public func setROIs(_ rois: [RTStructureSetROI]) {
        lock.withLock { _rois = rois }
    }

    public func getROIs() -> [RTStructureSetROI] {
        lock.withLock { _rois }
    }

    public func setROIVisibility(roiID: Int, visible: Bool) {
        lock.withLock {
            _rois = _rois.map { roi in
                roi.id == roiID
                    ? RTStructureSetROI(id: roi.id, name: roi.name, roiType: roi.roiType,
                                       color: roi.color, description: roi.description,
                                       isVisible: visible)
                    : roi
            }
        }
    }

    public func setIsodoseLevels(_ levels: [RTIsodoseLevel]) {
        lock.withLock { _isodoseLevels = levels }
    }

    public func getIsodoseLevels() -> [RTIsodoseLevel] {
        lock.withLock { _isodoseLevels }
    }

    public func addDVHCurve(_ curve: DVHCurve) {
        lock.withLock { _dvhCurves.append(curve) }
    }

    public func getDVHCurves() -> [DVHCurve] {
        lock.withLock { _dvhCurves }
    }

    public func setBeams(_ beams: [RTBeam]) {
        lock.withLock { _beams = beams }
    }

    public func getBeams() -> [RTBeam] {
        lock.withLock { _beams }
    }

    public func setFractionGroups(_ groups: [RTFractionGroup]) {
        lock.withLock { _fractionGroups = groups }
    }

    public func getFractionGroups() -> [RTFractionGroup] {
        lock.withLock { _fractionGroups }
    }

    // MARK: - Segmentation Methods

    public func updateSegmentOverlayState(_ state: SegmentOverlayState) {
        lock.withLock { _segmentOverlayState = state }
    }

    public func getSegmentOverlayState() -> SegmentOverlayState {
        lock.withLock { _segmentOverlayState }
    }

    public func setSegmentVisibility(segmentNumber: Int, visible: Bool) {
        lock.withLock {
            let updated = _segmentOverlayState.overlays.map { overlay in
                overlay.segmentNumber == segmentNumber
                    ? SegmentOverlay(segmentNumber: overlay.segmentNumber, label: overlay.label,
                                     algorithmType: overlay.algorithmType,
                                     categoryCode: overlay.categoryCode, typeCode: overlay.typeCode,
                                     color: overlay.color, opacity: overlay.opacity,
                                     isVisible: visible)
                    : overlay
            }
            _segmentOverlayState = SegmentOverlayState(
                overlays: updated,
                globalOpacity: _segmentOverlayState.globalOpacity,
                showLabels: _segmentOverlayState.showLabels)
        }
    }

    public func setGlobalOpacity(_ opacity: Double) {
        lock.withLock {
            _segmentOverlayState = SegmentOverlayState(
                overlays: _segmentOverlayState.overlays,
                globalOpacity: opacity,
                showLabels: _segmentOverlayState.showLabels)
        }
    }

    // MARK: - Parametric Map Methods

    public func updateParametricMapDisplayState(_ state: ParametricMapDisplayState) {
        lock.withLock { _parametricMapDisplayState = state }
    }

    public func getParametricMapDisplayState() -> ParametricMapDisplayState {
        lock.withLock { _parametricMapDisplayState }
    }

    public func setSUVParameters(_ params: SUVInputParameters?) {
        lock.withLock { _suvParameters = params }
    }

    public func getSUVParameters() -> SUVInputParameters? {
        lock.withLock { _suvParameters }
    }

    // MARK: - Waveform Methods

    public func updateWaveformSettings(_ settings: WaveformDisplaySettings) {
        lock.withLock { _waveformSettings = settings }
    }

    public func getWaveformSettings() -> WaveformDisplaySettings {
        lock.withLock { _waveformSettings }
    }

    public func setWaveformChannels(_ channels: [WaveformDisplayChannel]) {
        lock.withLock { _waveformChannels = channels }
    }

    public func getWaveformChannels() -> [WaveformDisplayChannel] {
        lock.withLock { _waveformChannels }
    }

    public func addCaliperMeasurement(_ measurement: WaveformCaliperMeasurement) {
        lock.withLock { _caliperMeasurements.append(measurement) }
    }

    public func getCaliperMeasurements() -> [WaveformCaliperMeasurement] {
        lock.withLock { _caliperMeasurements }
    }

    public func clearCaliperMeasurements() {
        lock.withLock { _caliperMeasurements = [] }
    }

    // MARK: - Video Methods

    public func setVideoDisplayState(_ state: VideoDisplayState?) {
        lock.withLock { _videoDisplayState = state }
    }

    public func getVideoDisplayState() -> VideoDisplayState? {
        lock.withLock { _videoDisplayState }
    }

    public func updatePlaybackState(isPlaying: Bool) {
        lock.withLock {
            guard var state = _videoDisplayState else { return }
            state = VideoDisplayState(
                isPlaying: isPlaying,
                currentFrameIndex: state.currentFrameIndex,
                playbackSpeed: state.playbackSpeed,
                totalFrames: state.totalFrames,
                frameRate: state.frameRate)
            _videoDisplayState = state
        }
    }

    public func advanceFrame() {
        lock.withLock {
            guard var state = _videoDisplayState else { return }
            let next = (state.currentFrameIndex + 1) % Swift.max(1, state.totalFrames)
            state = VideoDisplayState(
                isPlaying: state.isPlaying,
                currentFrameIndex: next,
                playbackSpeed: state.playbackSpeed,
                totalFrames: state.totalFrames,
                frameRate: state.frameRate)
            _videoDisplayState = state
        }
    }

    public func setCurrentFrame(_ index: Int) {
        lock.withLock {
            guard var state = _videoDisplayState else { return }
            let clamped = Swift.min(Swift.max(index, 0), state.totalFrames - 1)
            state = VideoDisplayState(
                isPlaying: state.isPlaying,
                currentFrameIndex: clamped,
                playbackSpeed: state.playbackSpeed,
                totalFrames: state.totalFrames,
                frameRate: state.frameRate)
            _videoDisplayState = state
        }
    }

    // MARK: - Document Methods

    public func setDocumentDisplayState(_ state: EncapsulatedDocumentDisplayState?) {
        lock.withLock { _documentDisplayState = state }
    }

    public func getDocumentDisplayState() -> EncapsulatedDocumentDisplayState? {
        lock.withLock { _documentDisplayState }
    }

    public func nextPage() {
        lock.withLock {
            guard var state = _documentDisplayState else { return }
            if state.currentPage < state.pageCount - 1 {
                state = EncapsulatedDocumentDisplayState(
                    documentType: state.documentType, isLoaded: state.isLoaded,
                    pageCount: state.pageCount, currentPage: state.currentPage + 1,
                    zoom: state.zoom, title: state.title)
            }
            _documentDisplayState = state
        }
    }

    public func previousPage() {
        lock.withLock {
            guard var state = _documentDisplayState else { return }
            if state.currentPage > 0 {
                state = EncapsulatedDocumentDisplayState(
                    documentType: state.documentType, isLoaded: state.isLoaded,
                    pageCount: state.pageCount, currentPage: state.currentPage - 1,
                    zoom: state.zoom, title: state.title)
            }
            _documentDisplayState = state
        }
    }

    // MARK: - WSI Methods

    public func updateWSIDisplayState(_ state: WSIDisplayState) {
        lock.withLock { _wsiDisplayState = state }
    }

    public func getWSIDisplayState() -> WSIDisplayState {
        lock.withLock { _wsiDisplayState }
    }

    public func setTileLevels(_ levels: [WSITileLevel]) {
        lock.withLock { _tileLevels = levels }
    }

    public func getTileLevels() -> [WSITileLevel] {
        lock.withLock { _tileLevels }
    }

    public func setOpticalPaths(_ paths: [WSIOpticalPath]) {
        lock.withLock { _opticalPaths = paths }
    }

    public func getOpticalPaths() -> [WSIOpticalPath] {
        lock.withLock { _opticalPaths }
    }

    public func toggleOpticalPath(id: String) {
        lock.withLock {
            _opticalPaths = _opticalPaths.map { path in
                path.opticalPathID == id
                    ? WSIOpticalPath(opticalPathID: path.opticalPathID,
                                     description: path.description,
                                     illuminationColor: path.illuminationColor,
                                     isVisible: !path.isVisible)
                    : path
            }
        }
    }

    // MARK: - Reset

    /// Resets all state to initial defaults.
    public func resetAll() {
        lock.withLock {
            _rois = []
            _selectedROIID = nil
            _isodoseLevels = []
            _dvhCurves = []
            _beams = []
            _fractionGroups = []
            _segmentOverlayState = SegmentOverlayState(overlays: [])
            _parametricMapDisplayState = ParametricMapDisplayState(
                mapType: .t1Mapping, colormapName: .hot, minValue: 0, maxValue: 3000)
            _suvParameters = nil
            _waveformSettings = WaveformDisplaySettings()
            _waveformChannels = []
            _caliperMeasurements = []
            _videoDisplayState = nil
            _documentDisplayState = nil
            _wsiDisplayState = WSIDisplayState(visibleOpticalPaths: [])
            _tileLevels = []
            _opticalPaths = []
        }
    }
}
