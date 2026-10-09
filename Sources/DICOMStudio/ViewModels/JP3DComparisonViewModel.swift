// JP3DComparisonViewModel.swift
// DICOMStudio
//
// ViewModel for the JP3D volumetric comparison viewer.
// Uses JP3DCodec (true 3D wavelet compression), NOT J2KSwiftCodec (per-frame 2D).
//
// NEMA-verified: 2026a, checked 2026-10-05 — carries no DICOM-standard data (JP3D bench state); PSNR uses 2^bitsAllocated − 1 as the peak, window defaults are UI values

import Foundation
import Observation
import DICOMKit
import DICOMCore

// MARK: - Mode Selection

/// JP3D compression mode options for the picker.
public enum JP3DModeSelection: String, CaseIterable, Sendable, Identifiable {
    case lossless      = "JP3D Lossless"
    case losslessHTJ2K = "JP3D HTJ2K Lossless"
    case lossy         = "JP3D Lossy"
    case lossyHTJ2K    = "JP3D HTJ2K Lossy"

    public var id: String { rawValue }

    public var isLossy: Bool {
        switch self {
        case .lossless, .losslessHTJ2K: return false
        case .lossy, .lossyHTJ2K:       return true
        }
    }

    func makeCodecMode(psnr: Double) -> JP3DCodec.CompressionMode {
        switch self {
        case .lossless:      return .lossless
        case .losslessHTJ2K: return .losslessHTJ2K
        case .lossy:         return .lossy(psnr: psnr)
        case .lossyHTJ2K:    return .lossyHTJ2K(psnr: psnr)
        }
    }
}

// MARK: - Decomposition Info

/// Wavelet decomposition parameters for the current volume + mode.
public struct JP3DDecompositionInfo: Sendable {
    public let levelsX: Int
    public let levelsY: Int
    public let levelsZ: Int
    public let qualityLayers: Int
    public let progressionOrder: String = "LRCP-S"
}

// MARK: - Compression State

public enum JP3DCompressionState: Sendable {
    case idle
    case compressing
    case complete(
        encodeMs: Double,
        decodeMs: Double,
        ratio: Double,
        rawBytes: Int,
        encodedBytes: Int,
        psnrDB: Double
    )
    case failed(String)
}

// MARK: - JP3DComparisonViewModel

@available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
@Observable
@MainActor
public final class JP3DComparisonViewModel {

    // MARK: - Child ViewModels

    public let rawVM = JP3DMPRViewModel()
    public let decodedVM = JP3DMPRViewModel()

    // MARK: - Shared Navigation

    public private(set) var axialIndex: Int = 0
    public private(set) var sagittalIndex: Int = 0
    public private(set) var coronalIndex: Int = 0
    public private(set) var windowCenter: Double = 40.0
    public private(set) var windowWidth: Double = 400.0

    public var maxAxialIndex: Int    { rawVM.dimensions?.maxSliceIndex(for: .axial)    ?? 0 }
    public var maxSagittalIndex: Int { rawVM.dimensions?.maxSliceIndex(for: .sagittal) ?? 0 }
    public var maxCoronalIndex: Int  { rawVM.dimensions?.maxSliceIndex(for: .coronal)  ?? 0 }

    // MARK: - Config

    public var selectedMode: JP3DModeSelection = .lossless
    public var lossyPSNRTarget: Double = 40.0

    // MARK: - State

    public private(set) var compressionState: JP3DCompressionState = .idle

    public var isCompressing: Bool {
        if case .compressing = compressionState { return true }
        return false
    }

    public var hasVolume: Bool      { rawVM.volume != nil }
    public var isLoadingVolume: Bool { rawVM.isLoading }

    public var volumeInfo: String {
        guard let dims = rawVM.dimensions else { return "" }
        let bits = rawVM.volume?.bitsAllocated ?? 16
        let mod  = rawVM.volume?.modality ?? "Unknown"
        return "\(mod) · \(dims.width) × \(dims.height) × \(dims.depth) · \(bits)-bit"
    }

    /// Wavelet decomposition parameters derived from the loaded volume + selected mode.
    public var decompositionInfo: JP3DDecompositionInfo? {
        guard let vol = rawVM.volume else { return nil }
        return JP3DDecompositionInfo(
            levelsX: min(3, floorLog2(vol.width)),
            levelsY: min(3, floorLog2(vol.height)),
            levelsZ: min(1, floorLog2(vol.depth)),
            qualityLayers: selectedMode.isLossy ? 3 : 1
        )
    }

    // MARK: - Private

    private var rawVolume: DICOMVolume?

    public init() {}

    // MARK: - Volume Loading

    public func loadVolume(from url: URL) async throws {
        compressionState = .idle
        try await rawVM.loadVolume(from: url)
        if let vol = rawVM.volume {
            rawVolume = vol
            decodedVM.setVolume(vol)
            syncFromRawVM()
        }
    }

    public func setVolume(_ volume: DICOMVolume) {
        rawVolume = volume
        rawVM.setVolume(volume)
        decodedVM.setVolume(volume)
        syncFromRawVM()
        compressionState = .idle
    }

    // MARK: - Navigation Setters

    public func setAxialIndex(_ index: Int) {
        let v = max(0, min(index, maxAxialIndex))
        axialIndex = v
        rawVM.setSliceIndex(v, for: .axial)
        decodedVM.setSliceIndex(v, for: .axial)
    }

    public func setSagittalIndex(_ index: Int) {
        let v = max(0, min(index, maxSagittalIndex))
        sagittalIndex = v
        rawVM.setSliceIndex(v, for: .sagittal)
        decodedVM.setSliceIndex(v, for: .sagittal)
    }

    public func setCoronalIndex(_ index: Int) {
        let v = max(0, min(index, maxCoronalIndex))
        coronalIndex = v
        rawVM.setSliceIndex(v, for: .coronal)
        decodedVM.setSliceIndex(v, for: .coronal)
    }

    public func setWindowLevel(center: Double, width: Double) {
        windowCenter = center
        windowWidth = max(1, width)
        rawVM.setWindowLevel(center: windowCenter, width: windowWidth)
        decodedVM.setWindowLevel(center: windowCenter, width: windowWidth)
    }

    public func handleClick(x: CGFloat, y: CGFloat, in plane: MPRPlane, viewSize: CGSize) {
        guard viewSize.width > 0, viewSize.height > 0 else { return }
        guard let dims = rawVM.dimensions else { return }
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

    // MARK: - JP3D Volumetric Compression

    public func runCompression() {
        guard let vol = rawVolume, !isCompressing else { return }
        compressionState = .compressing
        let mode = selectedMode
        let psnrTarget = lossyPSNRTarget

        Task {
            let result = await Self.encodeDecodeVolume(vol, mode: mode, psnrTarget: psnrTarget)
            switch result {
            case .success(let (decoded, encMs, decMs, rawBytes, encBytes, psnr)):
                decodedVM.setVolume(decoded)
                decodedVM.setSliceIndex(axialIndex,    for: .axial)
                decodedVM.setSliceIndex(sagittalIndex, for: .sagittal)
                decodedVM.setSliceIndex(coronalIndex,  for: .coronal)
                decodedVM.setWindowLevel(center: windowCenter, width: windowWidth)
                compressionState = .complete(
                    encodeMs: encMs,
                    decodeMs: decMs,
                    ratio: Double(rawBytes) / Double(max(1, encBytes)),
                    rawBytes: rawBytes,
                    encodedBytes: encBytes,
                    psnrDB: psnr
                )
            case .failure(let err):
                compressionState = .failed(err.localizedDescription)
            }
        }
    }

    // MARK: - Private Helpers

    private func syncFromRawVM() {
        axialIndex    = rawVM.axialIndex
        sagittalIndex = rawVM.sagittalIndex
        coronalIndex  = rawVM.coronalIndex
        windowCenter  = rawVM.windowCenter
        windowWidth   = rawVM.windowWidth
        decodedVM.setSliceIndex(axialIndex,    for: .axial)
        decodedVM.setSliceIndex(sagittalIndex, for: .sagittal)
        decodedVM.setSliceIndex(coronalIndex,  for: .coronal)
        decodedVM.setWindowLevel(center: windowCenter, width: windowWidth)
    }

    private func floorLog2(_ n: Int) -> Int {
        guard n > 1 else { return 0 }
        return Int(log2(Double(n)))
    }

    // MARK: - Background Worker (volumetric JP3D encode → decode)

    private static func encodeDecodeVolume(
        _ volume: DICOMVolume,
        mode: JP3DModeSelection,
        psnrTarget: Double
    ) async -> Result<(DICOMVolume, Double, Double, Int, Int, Double), Error> {
        await Task.detached(priority: .userInitiated) {
            let descriptor = PixelDataDescriptor(
                rows: volume.height,
                columns: volume.width,
                numberOfFrames: volume.depth,   // full depth — this is what makes JP3D volumetric
                bitsAllocated: volume.bitsAllocated,
                bitsStored: volume.bitsStored,
                highBit: volume.bitsStored - 1,
                isSigned: volume.isSigned,
                samplesPerPixel: 1,
                photometricInterpretation: .monochrome2,
                planarConfiguration: 0
            )

            let codec = JP3DCodec(compressionMode: mode.makeCodecMode(psnr: psnrTarget))

            let t0 = Date()
            let encoded: Data
            do { encoded = try await codec.encodeVolume(volume.pixelData, descriptor: descriptor) }
            catch { return .failure(error) }
            let encMs = Date().timeIntervalSince(t0) * 1_000

            let t1 = Date()
            let decodedData: Data
            do { decodedData = try await codec.decodeVolume(encoded, descriptor: descriptor) }
            catch { return .failure(error) }
            let decMs = Date().timeIntervalSince(t1) * 1_000

            let psnr = jp3dComputePSNR(
                raw: volume.pixelData,
                decoded: decodedData,
                bitsAllocated: volume.bitsAllocated
            )

            let decoded = DICOMVolume(
                width: volume.width, height: volume.height, depth: volume.depth,
                bitsAllocated: volume.bitsAllocated, bitsStored: volume.bitsStored,
                highBit: volume.highBit,
                isSigned: volume.isSigned,
                photometricInterpretation: volume.photometricInterpretation,
                spacingX: volume.spacingX, spacingY: volume.spacingY, spacingZ: volume.spacingZ,
                originX: volume.originX, originY: volume.originY, originZ: volume.originZ,
                pixelData: decodedData,
                modality: volume.modality,
                seriesInstanceUID: volume.seriesInstanceUID,
                studyInstanceUID: volume.studyInstanceUID
            )

            return .success((decoded, encMs, decMs, volume.pixelData.count, encoded.count, psnr))
        }.value
    }

}

// MARK: - PSNR (free function, not actor-isolated)

private func jp3dComputePSNR(raw: Data, decoded: Data, bitsAllocated: Int) -> Double {
    guard raw.count == decoded.count, raw.count > 0 else { return 0 }
    let maxVal = Double((1 << bitsAllocated) - 1)
    var sumSqDiff: Double = 0

    if bitsAllocated == 16 {
        let pixelCount = raw.count / 2
        raw.withUnsafeBytes { rp in
            decoded.withUnsafeBytes { dp in
                let rArr = rp.bindMemory(to: UInt16.self)
                let dArr = dp.bindMemory(to: UInt16.self)
                for i in 0..<pixelCount {
                    let diff = Double(rArr[i]) - Double(dArr[i])
                    sumSqDiff += diff * diff
                }
            }
        }
        let mse = sumSqDiff / Double(pixelCount)
        if mse == 0 { return .infinity }
        return 10.0 * log10((maxVal * maxVal) / mse)
    } else {
        for i in 0..<raw.count {
            let diff = Double(raw[i]) - Double(decoded[i])
            sumSqDiff += diff * diff
        }
        let mse = sumSqDiff / Double(raw.count)
        if mse == 0 { return .infinity }
        return 10.0 * log10((maxVal * maxVal) / mse)
    }
}
