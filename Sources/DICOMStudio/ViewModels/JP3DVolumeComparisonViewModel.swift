// JP3DVolumeComparisonViewModel.swift
// DICOMStudio

import Foundation
//
// NEMA-verified: 2026a, checked 2026-10-05 — codecOptions are DICOMCore TransferSyntax.selectableEncodings filtered by isJPEG2000 and named by SelectableEncoding.displayName (PS3.6 2026a Table A-1 names); the .4.90 default is an A-1 row; no other standard data
import Observation
import DICOMKit
import DICOMCore

// MARK: - VolumeCompressionState

public enum VolumeCompressionState: Sendable {
    case idle
    case compressing(framesCompleted: Int, totalFrames: Int)
    case complete(encodeMs: Double, decodeMs: Double, ratio: Double, rawBytes: Int, encodedBytes: Int)
    case failed(String)
}

// MARK: - JP3DVolumeComparisonViewModel

/// ViewModel for the full-blown 3D MPR comparison viewer.
///
/// Owns two ``JP3DMPRViewModel`` child VMs — one for the raw volume and one for the
/// J2KSwift-compressed reconstruction. All slice navigation and window/level are
/// driven through the comparison ViewModel so both sides always stay in sync.
@available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
@Observable
@MainActor
public final class JP3DVolumeComparisonViewModel {

    // MARK: - Child ViewModels

    public let rawVM = JP3DMPRViewModel()
    public let compressedVM = JP3DMPRViewModel()

    // MARK: - Shared Navigation State

    public private(set) var axialIndex: Int = 0
    public private(set) var sagittalIndex: Int = 0
    public private(set) var coronalIndex: Int = 0
    public private(set) var windowCenter: Double = 40.0
    public private(set) var windowWidth: Double = 400.0

    // MARK: - Computed Limits

    public var maxAxialIndex: Int    { rawVM.dimensions?.maxSliceIndex(for: .axial)    ?? 0 }
    public var maxSagittalIndex: Int { rawVM.dimensions?.maxSliceIndex(for: .sagittal) ?? 0 }
    public var maxCoronalIndex: Int  { rawVM.dimensions?.maxSliceIndex(for: .coronal)  ?? 0 }

    // MARK: - Volume Metadata

    public var volumeInfo: String {
        guard let dims = rawVM.dimensions else { return "" }
        let bits = rawVolume?.bitsAllocated ?? 16
        let modality = rawVolume?.modality ?? "Unknown"
        return "\(modality) · \(dims.width) × \(dims.height) × \(dims.depth) · \(bits)-bit"
    }

    public var hasVolume: Bool { rawVM.volume != nil }
    public var isLoadingVolume: Bool { rawVM.isLoading }

    // MARK: - Compression Config

    /// Selectable-encoding id (`SelectableEncoding.id`) chosen for compression.
    /// Keyed on id rather than the bare UID so the two `.91`/`.203` rows
    /// (Lossless vs Lossy) select and encode independently.
    public var selectedID: String = "1.2.840.10008.1.2.4.90"

    /// One selectable J2K/HTJ2K encoding, carrying the intent-aware lossless flag.
    public struct VolumeCodecOption: Identifiable, Sendable, Hashable {
        public let id: String
        public let uid: String
        public let name: String
        public let isLossless: Bool
    }

    /// Driven by the shared transfer-syntax catalog so the list stays canonical.
    /// `both`-capable UIDs (.91/.93/.203) appear as two rows (Lossless + Lossy).
    public let codecOptions: [VolumeCodecOption] = TransferSyntax.selectableEncodings
        .filter { $0.transferSyntax.isJPEG2000 }
        .map { VolumeCodecOption(id: $0.id, uid: $0.uid, name: $0.displayName, isLossless: $0.isLossless) }

    // MARK: - Compression State

    public private(set) var compressionState: VolumeCompressionState = .idle

    public var isCompressing: Bool {
        if case .compressing = compressionState { return true }
        return false
    }

    public var compressedCodecName: String {
        codecOptions.first(where: { $0.id == selectedID })?.name ?? selectedID
    }

    // MARK: - Private

    private var rawVolume: DICOMVolume?

    public init() {}

    // MARK: - Volume Loading

    /// Loads a DICOM volume from URL (directory of slices or JP3D encapsulated document).
    public func loadVolume(from url: URL) async throws {
        compressionState = .idle
        try await rawVM.loadVolume(from: url)
        if let vol = rawVM.volume {
            rawVolume = vol
            compressedVM.setVolume(vol)
            syncIndicesFromRawVM()
        }
    }

    /// Sets a pre-decoded volume directly.
    public func setVolume(_ volume: DICOMVolume) {
        rawVolume = volume
        rawVM.setVolume(volume)
        compressedVM.setVolume(volume)
        syncIndicesFromRawVM()
        compressionState = .idle
    }

    // MARK: - Navigation Setters (drive both child VMs simultaneously)

    public func setAxialIndex(_ index: Int) {
        let v = max(0, min(index, maxAxialIndex))
        axialIndex = v
        rawVM.setSliceIndex(v, for: .axial)
        compressedVM.setSliceIndex(v, for: .axial)
    }

    public func setSagittalIndex(_ index: Int) {
        let v = max(0, min(index, maxSagittalIndex))
        sagittalIndex = v
        rawVM.setSliceIndex(v, for: .sagittal)
        compressedVM.setSliceIndex(v, for: .sagittal)
    }

    public func setCoronalIndex(_ index: Int) {
        let v = max(0, min(index, maxCoronalIndex))
        coronalIndex = v
        rawVM.setSliceIndex(v, for: .coronal)
        compressedVM.setSliceIndex(v, for: .coronal)
    }

    public func setWindowLevel(center: Double, width: Double) {
        windowCenter = center
        windowWidth = max(1, width)
        rawVM.setWindowLevel(center: windowCenter, width: windowWidth)
        compressedVM.setWindowLevel(center: windowCenter, width: windowWidth)
    }

    public func scrollAxial(_ delta: Int)    { setAxialIndex(axialIndex + delta) }
    public func scrollSagittal(_ delta: Int) { setSagittalIndex(sagittalIndex + delta) }
    public func scrollCoronal(_ delta: Int)  { setCoronalIndex(coronalIndex + delta) }

    // MARK: - Click-to-Crosshair

    /// Maps a tap inside an MPR panel to updated slice indices on both child VMs.
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

    // MARK: - Compression

    public func runCompression() {
        guard let vol = rawVolume, !isCompressing else { return }
        compressionState = .compressing(framesCompleted: 0, totalFrames: vol.depth)
        let option = codecOptions.first(where: { $0.id == selectedID })
        let uid = option?.uid ?? selectedID
        // Intent-aware: for the two `.91`/`.203` rows this comes from the selected
        // catalog row, so Lossless vs Lossy encode differently despite the shared UID.
        let isLossless = option?.isLossless ?? true

        Task {
            let result = await Self.compressVolume(vol, targetUID: uid, isLossless: isLossless) { [weak self] done, total in
                Task { @MainActor [weak self] in
                    self?.compressionState = .compressing(framesCompleted: done, totalFrames: total)
                }
            }
            switch result {
            case .success(let (decoded, encMs, decMs, rawBytes, encBytes)):
                compressedVM.setVolume(decoded)
                compressedVM.setSliceIndex(axialIndex, for: .axial)
                compressedVM.setSliceIndex(sagittalIndex, for: .sagittal)
                compressedVM.setSliceIndex(coronalIndex, for: .coronal)
                compressedVM.setWindowLevel(center: windowCenter, width: windowWidth)
                compressionState = .complete(
                    encodeMs: encMs, decodeMs: decMs,
                    ratio: Double(rawBytes) / Double(max(1, encBytes)),
                    rawBytes: rawBytes, encodedBytes: encBytes
                )
            case .failure(let err):
                compressionState = .failed(err.localizedDescription)
            }
        }
    }

    // MARK: - Private Helpers

    private func syncIndicesFromRawVM() {
        axialIndex    = rawVM.axialIndex
        sagittalIndex = rawVM.sagittalIndex
        coronalIndex  = rawVM.coronalIndex
        windowCenter  = rawVM.windowCenter
        windowWidth   = rawVM.windowWidth
        compressedVM.setSliceIndex(axialIndex, for: .axial)
        compressedVM.setSliceIndex(sagittalIndex, for: .sagittal)
        compressedVM.setSliceIndex(coronalIndex, for: .coronal)
        compressedVM.setWindowLevel(center: windowCenter, width: windowWidth)
    }

    // MARK: - Background Compression Worker

    private static func compressVolume(
        _ volume: DICOMVolume,
        targetUID: String,
        isLossless: Bool,
        progressHandler: @escaping @Sendable (Int, Int) -> Void
    ) async -> Result<(DICOMVolume, Double, Double, Int, Int), Error> {
        await Task.detached(priority: .userInitiated) {
            let descriptor = PixelDataDescriptor(
                rows: volume.height,
                columns: volume.width,
                numberOfFrames: 1,
                bitsAllocated: volume.bitsAllocated,
                bitsStored: volume.bitsStored,
                highBit: volume.bitsStored - 1,
                isSigned: volume.isSigned,
                samplesPerPixel: 1,
                photometricInterpretation: .monochrome2,
                planarConfiguration: 0
            )
            let config = CompressionConfiguration(
                quality: isLossless ? .maximum : .medium,
                preferLossless: isLossless
            )
            let encoder = J2KSwiftCodec(encodingTransferSyntaxUID: targetUID)
            let decoder = J2KSwiftCodec()

            var totalEncoded = 0
            var allDecoded = Data()
            allDecoded.reserveCapacity(volume.pixelData.count)
            var encMs = 0.0
            var decMs = 0.0
            let total = volume.depth

            for i in 0..<total {
                guard let frame = volume.slice(at: i) else {
                    return .failure(DICOMError.parsingFailed("Missing frame \(i)"))
                }
                let t0 = Date()
                let enc: Data
                do { enc = try encoder.encodeFrame(frame, descriptor: descriptor, frameIndex: i, configuration: config) }
                catch { return .failure(error) }
                encMs += Date().timeIntervalSince(t0) * 1_000
                totalEncoded += enc.count

                let t1 = Date()
                let dec: Data
                do { dec = try decoder.decodeFrame(enc, descriptor: descriptor, frameIndex: 0) }
                catch { return .failure(error) }
                decMs += Date().timeIntervalSince(t1) * 1_000
                allDecoded.append(dec)
                progressHandler(i + 1, total)
            }

            let decoded = DICOMVolume(
                width: volume.width, height: volume.height, depth: volume.depth,
                bitsAllocated: volume.bitsAllocated, bitsStored: volume.bitsStored,
                highBit: volume.highBit,
                isSigned: volume.isSigned,
                photometricInterpretation: volume.photometricInterpretation,
                spacingX: volume.spacingX, spacingY: volume.spacingY, spacingZ: volume.spacingZ,
                originX: volume.originX, originY: volume.originY, originZ: volume.originZ,
                pixelData: allDecoded,
                modality: volume.modality,
                seriesInstanceUID: volume.seriesInstanceUID,
                studyInstanceUID: volume.studyInstanceUID
            )
            return .success((decoded, encMs, decMs, volume.pixelData.count, totalEncoded))
        }.value
    }
}
