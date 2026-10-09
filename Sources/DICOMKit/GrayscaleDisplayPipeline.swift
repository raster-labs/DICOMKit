// GrayscaleDisplayPipeline.swift
// DICOMKit
//
// The grayscale value chain of PS3.4 N.2 as one value: stored sample → Modality LUT
// (PS3.3 C.11.1) → VOI LUT or window (C.11.2) → Presentation LUT (C.11.6) → display
// byte. Shared by the presentation-state applicator, the exporter and both
// DICOMRenderKit backends, so the chain is written once (P-PIPELINE).
//
// NEMA-verified: 2026a, checked 2026-09-30 — the order Modality → VOI → Presentation LUT
// is PS3.4 2026a N.2; the window is applied to the Modality LUT's output ("after any
// Modality LUT or Rescale Slope and Intercept … have been applied", PS3.3 C.11.2.1.2.1);
// a VOI LUT's output 0…2^n−1 is normalised by 2^n−1 (C.11.2.1.1); with no VOI the full
// output range of the Modality LUT is the next input (C.11.6.1); INVERSE is
// "maximum value − output value" (C.11.6.1.2). Evaluated by Scripts/diff_renderkit.py.

import Foundation
import DICOMCore

/// The grayscale softcopy chain for a monochrome frame.
///
/// The pipeline does not look at the Photometric Interpretation: in a presentation
/// state the photometric of the referenced image is ignored (PS3.4 N.2), and for an
/// image on its own the caller supplies `PresentationLUT.inverse` for MONOCHROME1
/// (PS3.3 C.7.6.3.1.2, "displayed as white after any VOI gray scale
/// transformations"). ``standard(for:modalityLUT:voiLUT:presentationLUT:)`` does that.
public struct GrayscaleDisplayPipeline: Sendable, Hashable {
    /// Stored values → modality values; `nil` is the identity.
    public var modalityLUT: ModalityLUT?
    /// Modality values → values of interest; `nil` is C.11.6.1's full Modality LUT range.
    public var voiLUT: VOILUT?
    /// Values of interest → P-Values; `nil` is IDENTITY.
    public var presentationLUT: PresentationLUT?

    public init(modalityLUT: ModalityLUT? = nil, voiLUT: VOILUT? = nil,
                presentationLUT: PresentationLUT? = nil) {
        self.modalityLUT = modalityLUT
        self.voiLUT = voiLUT
        self.presentationLUT = presentationLUT
    }

    /// The chain for an image on its own: a MONOCHROME1 image with no Presentation
    /// LUT of its own is shown INVERSE (PS3.3 C.7.6.3.1.2); an explicit one wins.
    public static func standard(
        for photometric: PhotometricInterpretation,
        modalityLUT: ModalityLUT? = nil, voiLUT: VOILUT? = nil,
        presentationLUT: PresentationLUT? = nil
    ) -> GrayscaleDisplayPipeline {
        GrayscaleDisplayPipeline(
            modalityLUT: modalityLUT, voiLUT: voiLUT,
            presentationLUT: presentationLUT ?? (photometric == .monochrome1 ? .inverse : nil))
    }

    // MARK: Evaluation

    /// The modality value of a stored value (C.11.1).
    public func modalityValue(forStoredValue stored: Int) -> Double {
        modalityLUT?.apply(to: stored) ?? Double(stored)
    }

    /// The display value in 0…1 for a stored value (shifted, masked, sign-extended).
    public func normalizedValue(forStoredValue stored: Int, descriptor: PixelDataDescriptor) -> Double {
        let modality = modalityValue(forStoredValue: stored)

        let voi: Double
        switch voiLUT {
        case .window?:
            voi = voiLUT!.apply(to: modality)
        case .lut(let lut)?:
            // A table's output is 0…2^n−1 (C.11.2.1.1); the chain continues in 0…1.
            voi = lut.lookup(Self.tableIndex(modality)) / Double(lut.maxOutputValue)
        case nil:
            // C.11.6.1: with no VOI, the full output range of the Modality LUT is
            // the input range of the next stage.
            let low = descriptor.isSigned ? -(1 << (descriptor.bitsStored - 1)) : 0
            let high = low + (1 << descriptor.bitsStored) - 1
            // Ordered by value, so a negative slope still maps the minimum output to
            // the lowest luminance.
            let a = modalityValue(forStoredValue: low)
            let b = modalityValue(forStoredValue: high)
            let (lowValue, highValue) = (min(a, b), max(a, b))
            let range = highValue - lowValue
            voi = range > 0 ? (modality - lowValue) / range : 0
        }

        let presented = presentationLUT?.apply(to: voi) ?? voi
        return max(0.0, min(1.0, presented))
    }

    /// The display byte for a stored value (`WindowLUT.displayByte`, D63).
    public func displayByte(forStoredValue stored: Int, descriptor: PixelDataDescriptor) -> UInt8 {
        WindowLUT.displayByte(normalizedValue(forStoredValue: stored, descriptor: descriptor))
    }

    /// A VOI table index for a modality value: rounded, NaN to the first entry and
    /// clamped so the conversion to `Int` cannot trap (LUTData then clamps to its ends,
    /// C.11.2.1.1).
    static func tableIndex(_ value: Double) -> Int {
        guard !value.isNaN else { return Int.min / 2 }
        return Int(max(-1e15, min(1e15, value.rounded())))
    }

    // MARK: Tables

    /// The raw-cell → display-byte table for this chain, or `nil` when the
    /// descriptor's cells are wider than two bytes (evaluate per pixel then).
    ///
    /// Built over every possible cell exactly as `WindowLUT` builds its table
    /// (`PixelDataDescriptor.storedValue(fromCell:)`, then this chain), so a GPU
    /// indexing it stays byte-identical to the CPU. Cached (most recently used 4).
    public func table(for descriptor: PixelDataDescriptor) -> WindowLUT? {
        guard WindowLUT.canTabulate(descriptor) else { return nil }
        let key = TableKey(pipeline: self, entries: descriptor.bytesPerSample == 1 ? 256 : 65_536,
                           bitShift: descriptor.bitShift, storedBitMask: descriptor.storedBitMask,
                           isSigned: descriptor.isSigned, bitsStored: descriptor.bitsStored)
        if let hit = PipelineTableCache.shared.table(for: key) { return hit }
        var table = [UInt8](repeating: 0, count: key.entries)
        for cell in 0..<key.entries {
            table[cell] = displayByte(forStoredValue: descriptor.storedValue(fromCell: cell),
                                      descriptor: descriptor)
        }
        let lut = WindowLUT(table: table)
        PipelineTableCache.shared.insert(lut, for: key)
        return lut
    }

    struct TableKey: Hashable {
        let pipeline: GrayscaleDisplayPipeline
        let entries: Int
        let bitShift: Int
        let storedBitMask: Int
        let isSigned: Bool
        let bitsStored: Int
    }

    // MARK: Auto window

    /// A window that shows a frame's whole range: its lowest modality value black,
    /// its highest white, linear between.
    ///
    /// For integer modality values x1…x2 this is PS3.3 C.11.2.1.2.1's full-range
    /// LINEAR window (centre (x1+x2+1)/2, width x2−x1+1), written as the identical
    /// LINEAR_EXACT window (centre (x1+x2)/2, width x2−x1) so it also holds for a
    /// rescale slope other than 1 or a negative one. A flat frame is the unit-width
    /// threshold at its value, as that window gives. A toolkit policy, not a VOI the
    /// standard defines.
    public static func fullRangeWindow(modalityLUT: ModalityLUT?, storedRange: (min: Int, max: Int)) -> VOILUT {
        let pipeline = GrayscaleDisplayPipeline(modalityLUT: modalityLUT)
        var low = Double.infinity, high = -Double.infinity
        if case .lut? = modalityLUT, storedRange.max - storedRange.min <= 1 << 20 {
            for stored in storedRange.min...storedRange.max {
                let value = pipeline.modalityValue(forStoredValue: stored)
                low = min(low, value)
                high = max(high, value)
            }
        } else {
            let a = pipeline.modalityValue(forStoredValue: storedRange.min)
            let b = pipeline.modalityValue(forStoredValue: storedRange.max)
            low = min(a, b)
            high = max(a, b)
        }
        guard high > low else {
            return .window(center: low + 0.5, width: 1, explanation: nil, function: .linear)
        }
        return .window(center: (low + high) / 2, width: high - low, explanation: nil, function: .linearExact)
    }
}

// MARK: - Conversions

public extension LUTData {
    /// A file's VOI or Modality LUT Sequence table (``GrayscaleLUT``) as `LUTData`.
    init(_ table: GrayscaleLUT) {
        self.init(numberOfEntries: table.entries.count, firstValueMapped: table.firstMappedValue,
                  bitsPerEntry: table.bitsPerEntry, data: table.entries.map(Int.init),
                  explanation: table.explanation)
    }
}

public extension VOILUT {
    /// A window as a VOI transformation, keeping its function and explanation.
    init(_ window: WindowSettings) {
        self = .window(center: window.center, width: window.width,
                       explanation: window.explanation, function: window.function)
    }
}

// MARK: - Cache

final class PipelineTableCache: @unchecked Sendable {
    static let shared = PipelineTableCache()
    private let lock = NSLock()
    private var entries: [(key: GrayscaleDisplayPipeline.TableKey, lut: WindowLUT)] = []
    private let capacity = 4

    func table(for key: GrayscaleDisplayPipeline.TableKey) -> WindowLUT? {
        lock.lock(); defer { lock.unlock() }
        guard let index = entries.firstIndex(where: { $0.key == key }) else { return nil }
        let hit = entries.remove(at: index)
        entries.insert(hit, at: 0)
        return hit.lut
    }

    func insert(_ lut: WindowLUT, for key: GrayscaleDisplayPipeline.TableKey) {
        lock.lock(); defer { lock.unlock() }
        guard !entries.contains(where: { $0.key == key }) else { return }
        entries.insert((key, lut), at: 0)
        if entries.count > capacity { entries.removeLast() }
    }
}
