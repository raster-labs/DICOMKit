// ColorSampleLUT.swift
// DICOMCore — GPU_RENDERING_PLAN.md milestone M4
//
// The colour equivalents of `WindowLUT`: the two remaining per-pixel value maps in
// the renderer, each hoisted over its single input so they can be evaluated once
// per possible sample instead of once per pixel — and so a shader can consume them
// without doing any floating-point work.
// NEMA-verified: 2026a, checked 2026-09-25 — carries no DICOM-standard data (transcribed renderer arithmetic). C1 classification confirmed.

import Foundation

// MARK: - RGB channel normalisation

/// Maps a raw colour sample to its 8-bit display value.
///
/// The RGB path's per-channel chain — bit shift, stored-bit mask, scale to 0…255,
/// clamp — reads exactly one variable, the raw sample, just as the monochrome
/// window chain does. See ``WindowLUT`` for the full argument; this is the same
/// transformation applied to a different pure function.
///
/// One table serves all three channels: R, G and B share the descriptor's bit
/// shift, mask and stored-bit count, so the map is identical for each.
public struct ColorSampleLUT: Sendable, Equatable {
    /// 256 entries for one-byte samples, 65,536 otherwise.
    public let table: [UInt8]

    @inlinable public var count: Int { table.count }

    public init(table: [UInt8]) { self.table = table }

    @inlinable
    public subscript(rawValue: Int) -> UInt8 { table[rawValue] }

    /// Returns a cached table for a descriptor, building it on a miss.
    public static func normalisation(for descriptor: PixelDataDescriptor) -> ColorSampleLUT {
        ColorSampleLUTCache.shared.lut(for: Parameters(descriptor: descriptor))
    }

    /// Builds the table unconditionally, bypassing the cache.
    public static func makeNormalisation(for descriptor: PixelDataDescriptor) -> ColorSampleLUT {
        Parameters(descriptor: descriptor).build()
    }

    struct Parameters: Hashable {
        let entries: Int
        let bitShift: Int
        let storedBitMask: Int
        let maxValue: Int

        init(descriptor: PixelDataDescriptor) {
            self.entries = descriptor.bytesPerSample == 1 ? 256 : 65_536
            self.bitShift = descriptor.bitShift
            self.storedBitMask = descriptor.storedBitMask
            self.maxValue = (1 << descriptor.bitsStored) - 1
        }

        /// A transcription of `PixelDataRenderer.renderColorFrame`'s per-channel
        /// arithmetic, hoisted over the raw sample. Keep it literal — including
        /// the degenerate `maxValue == 0` case, where the scale is infinite and
        /// the clamp yields 255. That is what the scalar loop produces, and
        /// equality with it is the contract.
        func build() -> ColorSampleLUT {
            let scale = 255.0 / Double(maxValue)
            var table = [UInt8](repeating: 0, count: entries)
            table.withUnsafeMutableBufferPointer { out in
                for rawValue in 0..<entries {
                    let masked = (rawValue >> bitShift) & storedBitMask
                    out[rawValue] = UInt8(max(0, min(255, Double(masked) * scale)))
                }
            }
            return ColorSampleLUT(table: table)
        }
    }
}

final class ColorSampleLUTCache: @unchecked Sendable {
    static let shared = ColorSampleLUTCache()

    private let lock = NSLock()
    private var entries: [(parameters: ColorSampleLUT.Parameters, lut: ColorSampleLUT)] = []
    private let capacity = 4

    func lut(for parameters: ColorSampleLUT.Parameters) -> ColorSampleLUT {
        lock.lock()
        if let index = entries.firstIndex(where: { $0.parameters == parameters }) {
            let hit = entries.remove(at: index)
            entries.insert(hit, at: 0)
            lock.unlock()
            return hit.lut
        }
        lock.unlock()

        let built = parameters.build()

        lock.lock()
        if !entries.contains(where: { $0.parameters == parameters }) {
            entries.insert((parameters, built), at: 0)
            if entries.count > capacity { entries.removeLast() }
        }
        lock.unlock()
        return built
    }

    func removeAll() {
        lock.lock(); entries.removeAll(); lock.unlock()
    }
}

// MARK: - Palette colour

/// Maps a raw palette index to its display RGB, with the palette lookup and all
/// the bit handling already applied.
///
/// Three byte tables rather than one table of triples, because that is the shape a
/// shader indexes most cheaply and it keeps each table a plain `[UInt8]`.
public struct PaletteDisplayLUT: Sendable, Equatable {
    public let red: [UInt8]
    public let green: [UInt8]
    public let blue: [UInt8]

    @inlinable public var count: Int { red.count }

    public init(red: [UInt8], green: [UInt8], blue: [UInt8]) {
        self.red = red
        self.green = green
        self.blue = blue
    }

    /// Builds the display tables for a descriptor + palette pair.
    ///
    /// Not cached: a palette belongs to one file, is consulted once per render, and
    /// `PaletteColorLUT` is a value type with no cheap identity to key on. The
    /// build is 256 or 65,536 lookups, which is already less work than one frame.
    public static func make(
        descriptor: PixelDataDescriptor,
        palette: PaletteColorLUT
    ) -> PaletteDisplayLUT {
        let entries = descriptor.bytesPerSample == 1 ? 256 : 65_536
        let bitShift = descriptor.bitShift
        let storedBitMask = descriptor.storedBitMask
        let isSigned = descriptor.isSigned
        let bitsStored = descriptor.bitsStored

        var red = [UInt8](repeating: 0, count: entries)
        var green = [UInt8](repeating: 0, count: entries)
        var blue = [UInt8](repeating: 0, count: entries)

        for rawValue in 0..<entries {
            // Transcribed from `PixelDataRenderer.renderPaletteColorFrame`.
            let shiftedValue = rawValue >> bitShift
            var maskedValue = shiftedValue & storedBitMask
            if isSigned {
                let signBit = 1 << (bitsStored - 1)
                if maskedValue & signBit != 0 {
                    maskedValue = maskedValue - (1 << bitsStored)
                }
            }
            let (r, g, b) = palette.lookup(maskedValue)
            red[rawValue] = r
            green[rawValue] = g
            blue[rawValue] = b
        }
        return PaletteDisplayLUT(red: red, green: green, blue: blue)
    }

    /// Builds the display tables for a *windowed monochrome* frame shown through
    /// a pseudo-colour palette.
    ///
    /// The palette a reader picks is not the file's own PALETTE COLOR LUT: it
    /// recolours the *displayed level*, after the window, exactly as
    /// `ImagePreprocessor.colorize` does on the print path and
    /// `FrameRenderer.colorized` does on the CPU preview path. That makes it a
    /// composition of two tables that are both indexed by the raw assembled
    /// sample — window (raw → grey byte) then palette (grey byte → RGB) — so it
    /// folds into the same three byte tables the palette kernel already indexes,
    /// and a monochrome frame can take the GPU path in colour with no new shader
    /// and no second implementation of the lookup.
    ///
    /// - Parameters:
    ///   - window: the grayscale table the monochrome kernel would have used.
    ///   - entries: the palette's 256 RGB triples, in index order.
    public static func make(
        window: WindowLUT,
        entries: [(red: UInt8, green: UInt8, blue: UInt8)]
    ) -> PaletteDisplayLUT {
        guard let last = entries.indices.last else {
            let grey = window.table
            return PaletteDisplayLUT(red: grey, green: grey, blue: grey)
        }
        let count = window.table.count
        var red = [UInt8](repeating: 0, count: count)
        var green = [UInt8](repeating: 0, count: count)
        var blue = [UInt8](repeating: 0, count: count)
        for rawValue in 0..<count {
            // Clamped the same way the CPU counterpart clamps it, so a palette
            // with fewer than 256 entries lands on the same colour on both paths.
            let entry = entries[min(last, Int(window.table[rawValue]))]
            red[rawValue] = entry.red
            green[rawValue] = entry.green
            blue[rawValue] = entry.blue
        }
        return PaletteDisplayLUT(red: red, green: green, blue: blue)
    }
}
