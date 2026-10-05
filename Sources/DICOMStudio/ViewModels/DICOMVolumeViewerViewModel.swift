// DICOMVolumeViewerViewModel.swift
// DICOMStudio — Enterprise 3D MPR viewer ViewModel
//
// NEMA-verified: 2026a, checked 2026-10-05 — the 8 CT viewer presets claim nothing standard-defined (clinical HU windows, PS3.3 2026a C.11.1.1.2); the modality codes it keys on (CT, MR, PT) are C.7.3.1.1.1 Defined Terms; ViewerLUT names are this app's ramps (not PS3.6 Annex B palettes); window width floor 1 is the LINEAR minimum (C.11.2.1.2.1); checked by Scripts/diff_studio_g2_viewer.py

import Foundation
import Observation
import CoreGraphics
import DICOMKit

// MARK: - ViewerLayout

public enum ViewerLayout: String, CaseIterable, Sendable, Identifiable {
    case quad        = "2×2 Quad"
    case triplanar   = "Triplanar"
    case axialFocus  = "Axial Focus"
    case single      = "Single"

    public var id: String { rawValue }
    public var symbol: String {
        switch self {
        case .quad:       return "square.grid.2x2"
        case .triplanar:  return "rectangle.split.3x1"
        case .axialFocus: return "rectangle.righthalf.inset.filled"
        case .single:     return "rectangle.fill"
        }
    }
}

// MARK: - ViewerTool

public enum ViewerTool: String, CaseIterable, Sendable, Identifiable {
    case navigate = "Navigate"
    case distance = "Distance"
    case angle    = "Angle"

    public var id: String { rawValue }
    public var symbol: String {
        switch self {
        case .navigate: return "arrow.up.and.down.and.arrow.left.and.right"
        case .distance: return "ruler"
        case .angle:    return "angle"
        }
    }
    public var requiredPoints: Int { self == .angle ? 3 : 2 }
}

// MARK: - ViewerLUT

public enum ViewerLUT: String, CaseIterable, Sendable, Identifiable {
    case grayscale = "Grayscale"
    case inverted  = "Inverted"
    case hotIron   = "Hot Iron"
    case pet       = "PET"
    case rainbow   = "Rainbow"
    case hotMetal  = "Hot Metal"

    public var id: String { rawValue }
    public var isGrayscale: Bool { self == .grayscale }
    public var isInverted:  Bool { self == .inverted }
    public var isColor: Bool { !isGrayscale && !isInverted }

    public var colorEntries: [ColorEntry] {
        switch self {
        case .grayscale, .inverted: return ColorLUTHelpers.grayscalePalette()
        case .hotIron:              return ColorLUTHelpers.hotIronPalette()
        case .pet:                  return ColorLUTHelpers.petPalette()
        case .rainbow:              return ColorLUTHelpers.rainbowPalette()
        case .hotMetal:             return ColorLUTHelpers.hotMetalPalette()
        }
    }
}

// MARK: - PanelMeasurement

/// A finalized measurement anchored to a specific plane and slice.
public struct PanelMeasurement: Identifiable, Sendable {
    public let id: UUID
    public let plane: MPRPlane
    public let sliceIndex: Int
    /// Normalised [0,1] × [0,1] coordinates for each control point.
    public let points: [CGPoint]
    /// Formatted result string shown at the measurement label position.
    public let label: String
    public let isMeasureAngle: Bool

    public init(id: UUID = UUID(), plane: MPRPlane, sliceIndex: Int,
                points: [CGPoint], label: String, isMeasureAngle: Bool) {
        self.id = id; self.plane = plane; self.sliceIndex = sliceIndex
        self.points = points; self.label = label; self.isMeasureAngle = isMeasureAngle
    }
}

// MARK: - VolumeMetadata

public struct VolumeMetadata: Sendable {
    public let modality: String
    public let dimensions: String
    public let spacing: String
    public let physicalSize: String
    public let memorySize: String
}

// MARK: - DICOMVolumeViewerViewModel

@available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
@Observable
@MainActor
public final class DICOMVolumeViewerViewModel {

    // MARK: - Child VM

    public let mprVM = JP3DMPRViewModel()

    // MARK: - Navigation

    public private(set) var axialIndex: Int    = 0
    public private(set) var sagittalIndex: Int = 0
    public private(set) var coronalIndex: Int  = 0
    public private(set) var windowCenter: Double = 40.0
    public private(set) var windowWidth: Double  = 400.0

    public var maxAxialIndex: Int    { mprVM.dimensions?.maxSliceIndex(for: .axial)    ?? 0 }
    public var maxSagittalIndex: Int { mprVM.dimensions?.maxSliceIndex(for: .sagittal) ?? 0 }
    public var maxCoronalIndex: Int  { mprVM.dimensions?.maxSliceIndex(for: .coronal)  ?? 0 }

    public var hasVolume: Bool    { mprVM.volume != nil }
    public var isLoading: Bool    { mprVM.isLoading }
    public var errorMessage: String? { mprVM.errorMessage }

    // MARK: - Layout & Tool

    public var layout: ViewerLayout  = .quad
    public var singlePlane: MPRPlane = .axial
    public var activeTool: ViewerTool = .navigate

    // MARK: - Display

    public var selectedPreset: WindowLevelPreset? = nil
    public var lut: ViewerLUT = .grayscale
    public var showDICOMOverlay: Bool = true
    public private(set) var metadata: VolumeMetadata?

    // MARK: - Thick Slab / Projection

    public var slabThicknessMM: Double = 0 {
        didSet { if slabThicknessMM > 0 { recomputeAllMIPBuffers() } }
    }
    public var projectionMode: ProjectionMode = .mip {
        didSet { if slabThicknessMM > 0 { recomputeAllMIPBuffers() } }
    }

    private var mipAxialBuffer: Data?
    private var mipSagittalBuffer: Data?
    private var mipCoronalBuffer: Data?

    // MARK: - Zoom / Pan

    public var syncZoom: Bool = false   // when true, all planes share zoom/pan
    public var axialZoom: CGFloat    = 1.0
    public var sagittalZoom: CGFloat = 1.0
    public var coronalZoom: CGFloat  = 1.0
    public var axialPan: CGSize      = .zero
    public var sagittalPan: CGSize   = .zero
    public var coronalPan: CGSize    = .zero

    // MARK: - Cine

    public private(set) var cineState: PlaybackState     = .stopped
    public var cinePlane: MPRPlane     = .axial
    public var cineFPS: Double         = CinePlaybackHelpers.defaultFPS
    public var cineMode: PlaybackMode  = .loop
    private var cineDirection: PlaybackDirection = .forward
    private var cineTimer: Timer?

    // MARK: - Measurements

    public private(set) var measurements: [PanelMeasurement] = []
    public private(set) var pendingPoints: [CGPoint] = []
    public private(set) var pendingPlane: MPRPlane? = nil

    // MARK: - Crosshair HU

    public var crosshairHUValue: Int? {
        guard let vol = mprVM.volume else { return nil }
        return vol.voxel(x: sagittalIndex, y: coronalIndex, z: axialIndex)
    }

    // MARK: - Standard Presets

    public static let viewerPresets: [WindowLevelPreset] = [
        WindowLevelPreset(name: "Brain",       center: 40,   width: 80,   modality: "CT"),
        WindowLevelPreset(name: "Lung",        center: -600, width: 1500, modality: "CT"),
        WindowLevelPreset(name: "Bone",        center: 300,  width: 1500, modality: "CT"),
        WindowLevelPreset(name: "Abdomen",     center: 40,   width: 400,  modality: "CT"),
        WindowLevelPreset(name: "Soft Tissue", center: 40,   width: 350,  modality: "CT"),
        WindowLevelPreset(name: "Chest",       center: 40,   width: 400,  modality: "CT"),
        WindowLevelPreset(name: "Spine",       center: 400,  width: 2500, modality: "CT"),
        WindowLevelPreset(name: "Angio",       center: 250,  width: 800,  modality: "CT"),
    ]

    public init() {}

    // MARK: - Volume Loading

    public func loadVolume(from url: URL) async throws {
        try await mprVM.loadVolume(from: url)
        if let vol = mprVM.volume {
            syncFromMPRVM()
            metadata = buildMetadata(for: vol)
            hangingProtocol(for: vol)
        }
    }

    // MARK: - Navigation

    public func setAxialIndex(_ index: Int) {
        let v = max(0, min(index, maxAxialIndex))
        axialIndex = v
        mprVM.setSliceIndex(v, for: .axial)
        if slabThicknessMM > 0 { recomputeMIPBuffer(for: .axial) }
    }

    public func setSagittalIndex(_ index: Int) {
        let v = max(0, min(index, maxSagittalIndex))
        sagittalIndex = v
        mprVM.setSliceIndex(v, for: .sagittal)
        if slabThicknessMM > 0 { recomputeMIPBuffer(for: .sagittal) }
    }

    public func setCoronalIndex(_ index: Int) {
        let v = max(0, min(index, maxCoronalIndex))
        coronalIndex = v
        mprVM.setSliceIndex(v, for: .coronal)
        if slabThicknessMM > 0 { recomputeMIPBuffer(for: .coronal) }
    }

    public func sliceIndex(for plane: MPRPlane) -> Int {
        switch plane { case .axial: axialIndex; case .sagittal: sagittalIndex; case .coronal: coronalIndex }
    }

    // MARK: - Window / Level

    public func setWindowLevel(center: Double, width: Double) {
        windowCenter = center
        windowWidth  = max(1, width)
        mprVM.setWindowLevel(center: windowCenter, width: windowWidth)
        selectedPreset = nil
        if slabThicknessMM > 0 { recomputeAllMIPBuffers() }
    }

    public func applyPreset(_ preset: WindowLevelPreset) {
        selectedPreset = preset
        windowCenter   = preset.center
        windowWidth    = preset.width
        mprVM.setWindowLevel(center: preset.center, width: preset.width)
        if slabThicknessMM > 0 { recomputeAllMIPBuffers() }
    }

    // MARK: - Click-to-Crosshair

    public func handleClick(x: CGFloat, y: CGFloat, in plane: MPRPlane, viewSize: CGSize) {
        guard viewSize.width > 0, viewSize.height > 0 else { return }
        guard let dims = mprVM.dimensions else { return }
        let nx = Double(x) / Double(viewSize.width)
        let ny = Double(y) / Double(viewSize.height)
        switch plane {
        case .axial:
            setSagittalIndex(Int(nx * Double(dims.width)))
            setCoronalIndex(Int(ny * Double(dims.height)))
        case .sagittal:
            setCoronalIndex(Int(nx * Double(dims.height)))
            setAxialIndex(Int(ny * Double(dims.depth)))
        case .coronal:
            setSagittalIndex(Int(nx * Double(dims.width)))
            setAxialIndex(Int(ny * Double(dims.depth)))
        }
    }

    // MARK: - Zoom / Pan

    public func zoom(for plane: MPRPlane) -> CGFloat {
        switch plane { case .axial: axialZoom; case .sagittal: sagittalZoom; case .coronal: coronalZoom }
    }

    public func pan(for plane: MPRPlane) -> CGSize {
        switch plane { case .axial: axialPan; case .sagittal: sagittalPan; case .coronal: coronalPan }
    }

    public func setZoom(_ z: CGFloat, for plane: MPRPlane) {
        let clamped = max(0.5, min(8.0, z))
        if syncZoom {
            axialZoom = clamped; sagittalZoom = clamped; coronalZoom = clamped
        } else {
            switch plane { case .axial: axialZoom = clamped; case .sagittal: sagittalZoom = clamped; case .coronal: coronalZoom = clamped }
        }
    }

    public func adjustPan(_ delta: CGSize, for plane: MPRPlane) {
        func add(_ base: CGSize) -> CGSize {
            CGSize(width: base.width + delta.width, height: base.height + delta.height)
        }
        if syncZoom {
            axialPan = add(axialPan); sagittalPan = add(sagittalPan); coronalPan = add(coronalPan)
        } else {
            switch plane {
            case .axial:    axialPan    = add(axialPan)
            case .sagittal: sagittalPan = add(sagittalPan)
            case .coronal:  coronalPan  = add(coronalPan)
            }
        }
    }

    /// Adjusts W/L based on mouse drag delta (right-drag or ctrl+drag).
    /// dx → width, dy → center.  Scale: 4 HU per pixel.
    public func adjustWindowLevel(dx: Double, dy: Double) {
        let newCenter = windowCenter - dy * 4.0
        let newWidth  = max(1, windowWidth + dx * 4.0)
        setWindowLevel(center: newCenter, width: newWidth)
    }

    public func resetPanZoom(for plane: MPRPlane? = nil) {
        let planes: [MPRPlane] = plane.map { [$0] } ?? MPRPlane.allCases
        for p in planes {
            switch p {
            case .axial:    axialZoom    = 1; axialPan    = .zero
            case .sagittal: sagittalZoom = 1; sagittalPan = .zero
            case .coronal:  coronalZoom  = 1; coronalPan  = .zero
            }
        }
    }

    // MARK: - Cine

    public func startCine() {
        guard hasVolume else { return }
        cineState = .playing
        let interval = CinePlaybackHelpers.timerInterval(for: cineFPS)
        cineTimer?.invalidate()
        cineTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.stepCineFrame() }
        }
    }

    public func pauseCine() {
        cineTimer?.invalidate()
        cineTimer = nil
        cineState = .paused
    }

    public func stopCine() {
        cineTimer?.invalidate()
        cineTimer = nil
        cineState = .stopped
        cineDirection = .forward
    }

    public func toggleCine() {
        switch cineState {
        case .stopped, .paused: startCine()
        case .playing:          pauseCine()
        }
    }

    public func stepCine(delta: Int) {
        let total = maxForPlane(cinePlane) + 1
        let cur   = sliceIndex(for: cinePlane)
        let next  = ((cur + delta) % total + total) % total
        setSliceForCinePlane(next)
    }

    public func setCineFPS(_ fps: Double) {
        cineFPS = CinePlaybackHelpers.clampFPS(fps)
        if cineState == .playing {
            cineTimer?.invalidate()
            startCine()
        }
    }

    // MARK: - Measurements

    /// Places a measurement point at a normalised view-space position.
    public func placeMeasurementPoint(at viewPt: CGPoint, in plane: MPRPlane, viewSize: CGSize) {
        guard viewSize.width > 0, viewSize.height > 0 else { return }
        let norm = CGPoint(x: viewPt.x / viewSize.width, y: viewPt.y / viewSize.height)

        // If user switches plane mid-measurement, cancel the pending one.
        if pendingPlane != nil && pendingPlane != plane { cancelMeasurement() }

        pendingPlane  = plane
        pendingPoints.append(norm)

        let required = activeTool.requiredPoints
        if pendingPoints.count >= required {
            finalizeMeasurement(in: plane)
        }
    }

    public func cancelMeasurement() {
        pendingPoints = []
        pendingPlane  = nil
    }

    public func clearMeasurements(in plane: MPRPlane? = nil) {
        if let p = plane {
            measurements.removeAll { $0.plane == p }
        } else {
            measurements.removeAll()
        }
    }

    public func measurements(in plane: MPRPlane, at sliceIndex: Int) -> [PanelMeasurement] {
        measurements.filter { $0.plane == plane && abs($0.sliceIndex - sliceIndex) <= 1 }
    }

    // MARK: - Display Buffer (slab or thin slice)

    public func displayBuffer(for plane: MPRPlane) -> Data? {
        if slabThicknessMM > 0 {
            switch plane { case .axial: return mipAxialBuffer; case .sagittal: return mipSagittalBuffer; case .coronal: return mipCoronalBuffer }
        }
        switch plane { case .axial: return mprVM.axialBuffer; case .sagittal: return mprVM.sagittalBuffer; case .coronal: return mprVM.coronalBuffer }
    }

    /// Returns a `CGImage` applying the current LUT (and inversion if selected).
    public func cgImage(for plane: MPRPlane) -> CGImage? {
        guard let dims = mprVM.dimensions, let buf = displayBuffer(for: plane) else { return nil }
        let (w, h) = MPRHelpers.sliceDimensions(plane: plane, dimensions: dims)
        if lut.isGrayscale { return JP3DMPRRenderHelpers.cgImage(from: buf, width: w, height: h) }
        if lut.isInverted  { return JP3DMPRRenderHelpers.cgImage(from: EnterpriseRenderHelpers.invertBuffer(buf), width: w, height: h) }
        return EnterpriseRenderHelpers.cgImageWithLUT(buffer: buf, width: w, height: h, lut: lut.colorEntries)
    }

    // MARK: - Reference Line Helpers

    public func refLineT(refPlane: MPRPlane, displayPlane: MPRPlane) -> Double? {
        guard let dims = mprVM.dimensions else { return nil }
        return MPRHelpers.referenceLinePosition(
            referencePlane: refPlane,
            referenceSlice: sliceIndex(for: refPlane),
            displayPlane: displayPlane,
            dimensions: dims
        )
    }

    // MARK: - Calibration (for distance measurements)

    public func pixelSpacingMM(for plane: MPRPlane) -> (x: Double, y: Double) {
        guard let dims = mprVM.dimensions else { return (1, 1) }
        let s = MPRHelpers.slicePixelSpacing(plane: plane, dimensions: dims)
        return (s.spacingX, s.spacingY)
    }

    public func sliceDimensions(for plane: MPRPlane) -> (width: Int, height: Int) {
        guard let dims = mprVM.dimensions else { return (1, 1) }
        return MPRHelpers.sliceDimensions(plane: plane, dimensions: dims)
    }

    public func slicePositionMM(for plane: MPRPlane) -> Double {
        guard let dims = mprVM.dimensions else { return 0 }
        return MPRHelpers.slicePosition(index: sliceIndex(for: plane), plane: plane, dimensions: dims)
    }

    // MARK: - Private Helpers

    private func syncFromMPRVM() {
        axialIndex    = mprVM.axialIndex
        sagittalIndex = mprVM.sagittalIndex
        coronalIndex  = mprVM.coronalIndex
        windowCenter  = mprVM.windowCenter
        windowWidth   = mprVM.windowWidth
    }

    private func recomputeAllMIPBuffers() {
        guard let vol = mprVM.volume, let dims = mprVM.dimensions else { return }
        for p in MPRPlane.allCases { recomputeMIPBufferInner(plane: p, vol: vol, dims: dims) }
    }

    private func recomputeMIPBuffer(for plane: MPRPlane) {
        guard let vol = mprVM.volume, let dims = mprVM.dimensions else { return }
        recomputeMIPBufferInner(plane: plane, vol: vol, dims: dims)
    }

    private func recomputeMIPBufferInner(plane: MPRPlane, vol: DICOMVolume, dims: VolumeDimensionsModel) {
        let buf = EnterpriseRenderHelpers.thickSlabBuffer(
            volume: vol, plane: plane, centerIndex: sliceIndex(for: plane),
            slabThicknessMM: slabThicknessMM, projectionMode: projectionMode,
            windowCenter: windowCenter, windowWidth: windowWidth, dimensions: dims
        )
        switch plane { case .axial: mipAxialBuffer = buf; case .sagittal: mipSagittalBuffer = buf; case .coronal: mipCoronalBuffer = buf }
    }

    private func stepCineFrame() {
        let total = maxForPlane(cinePlane) + 1
        guard total > 1 else { return }
        let cur = sliceIndex(for: cinePlane)
        let (next, newDir, shouldStop) = CinePlaybackHelpers.nextFrame(
            current: cur, total: total, mode: cineMode, direction: cineDirection)
        cineDirection = newDir
        if shouldStop { stopCine(); return }
        setSliceForCinePlane(next)
    }

    private func setSliceForCinePlane(_ index: Int) {
        switch cinePlane {
        case .axial:    setAxialIndex(index)
        case .sagittal: setSagittalIndex(index)
        case .coronal:  setCoronalIndex(index)
        }
    }

    private func maxForPlane(_ plane: MPRPlane) -> Int {
        switch plane { case .axial: maxAxialIndex; case .sagittal: maxSagittalIndex; case .coronal: maxCoronalIndex }
    }

    private func finalizeMeasurement(in plane: MPRPlane) {
        let pts  = pendingPoints
        let tool = activeTool
        let idx  = sliceIndex(for: plane)
        pendingPoints = []
        pendingPlane  = nil

        guard let dims = mprVM.dimensions else { return }
        let (sliceW, sliceH) = MPRHelpers.sliceDimensions(plane: plane, dimensions: dims)
        let (spX, spY) = pixelSpacingMM(for: plane)

        let label: String
        let isAngle: Bool

        if tool == .distance, pts.count >= 2 {
            let dx = (pts[1].x - pts[0].x) * Double(sliceW) * spX
            let dy = (pts[1].y - pts[0].y) * Double(sliceH) * spY
            let mm = sqrt(dx * dx + dy * dy)
            label   = String(format: "%.1f mm", mm)
            isAngle = false
        } else if tool == .angle, pts.count >= 3 {
            let v  = pts[0]; let p1 = pts[1]; let p2 = pts[2]
            let ax = (p1.x - v.x) * Double(sliceW) * spX
            let ay = (p1.y - v.y) * Double(sliceH) * spY
            let bx = (p2.x - v.x) * Double(sliceW) * spX
            let by = (p2.y - v.y) * Double(sliceH) * spY
            let dot  = ax * bx + ay * by
            let magA = sqrt(ax * ax + ay * ay)
            let magB = sqrt(bx * bx + by * by)
            guard magA > 0, magB > 0 else { return }
            let angle = acos(max(-1, min(1, dot / (magA * magB)))) * 180.0 / .pi
            label   = String(format: "%.1f°", angle)
            isAngle = true
        } else { return }

        measurements.append(PanelMeasurement(
            plane: plane, sliceIndex: idx, points: pts, label: label, isMeasureAngle: isAngle))
    }

    private func hangingProtocol(for vol: DICOMVolume) {
        guard let mod = vol.modality else { return }
        switch mod.uppercased() {
        case "CT":
            applyPreset(WindowLevelPreset(name: "Abdomen", center: 40, width: 400, modality: "CT"))
        case "MR":
            applyPreset(WindowLevelPreset(name: "T1", center: 500, width: 1000, modality: "MR"))
        case "PT":
            lut = .pet
        default:
            break
        }
    }

    private func buildMetadata(for vol: DICOMVolume) -> VolumeMetadata {
        let mb  = Double(vol.pixelData.count) / 1_048_576
        let mem = mb >= 1 ? String(format: "%.1f MB", mb) : String(format: "%.0f KB", mb * 1024)
        return VolumeMetadata(
            modality: vol.modality ?? "Unknown",
            dimensions: "\(vol.width) × \(vol.height) × \(vol.depth)",
            spacing: String(format: "%.2f × %.2f × %.2f mm", vol.spacingX, vol.spacingY, vol.spacingZ),
            physicalSize: String(format: "%.0f × %.0f × %.0f mm",
                                 Double(vol.width) * vol.spacingX,
                                 Double(vol.height) * vol.spacingY,
                                 Double(vol.depth) * vol.spacingZ),
            memorySize: mem
        )
    }
}
