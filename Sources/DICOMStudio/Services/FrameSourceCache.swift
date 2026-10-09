// FrameSourceCache.swift
// DICOMStudio
//
// DICOM Studio — the decoded frames behind a re-render.
//
// NEMA-verified: 2026a, checked 2026-10-05 — carries no DICOM-standard data (decoded-pixel cache; the Palette Color LUT it keeps per file is read by DICOMKit)
//
// Windowing, zooming or panning a film cell changes how a frame is *shown*, not
// which frame it is. Without this, every mouse delta re-read the file from disk
// and re-decoded its pixels — for a JPEG 2000 CT that is tens of milliseconds
// per event, which is exactly the lag a window/level drag feels as stutter.
// Keeping the decoded pixels for the handful of files being worked on turns each
// subsequent render into a window mapping.

import Foundation
import DICOMCore
import DICOMKit
import DICOMRenderKit

#if canImport(CoreGraphics)
import CoreGraphics

/// A file's decoded pixels, ready to render at any window.
struct FrameSource: Sendable {
    let file: DICOMFile
    let pixelData: PixelData
    let paletteLUT: PaletteColorLUT?
}

/// Keeps the decoded pixels of the files currently being looked at.
///
/// The decoding itself happens off this actor. The cache is the shared state and
/// has to be serialised; a JPEG 2000 decode is not, and holding the actor across
/// one turned a film of sixteen cells into sixteen decodes in a row.
actor FrameSourceCache {

    static let shared = FrameSourceCache()

    /// How much decoded pixel data to hold, in bytes.
    ///
    /// A budget rather than a file count, because the files differ by two orders
    /// of magnitude: a CT slice is half a megabyte and a mammogram is twenty-odd.
    /// A count small enough to be safe for the mammogram — it used to be three —
    /// is far too small for the thing this cache exists to make fast: a 4×4 film
    /// whose sixteen cells are all being windowed. Every drag on the first cell
    /// then re-read and re-decoded its file, because loading the other fifteen
    /// had evicted it.
    private static let budgetBytes = 256 * 1024 * 1024

    /// Largest decoded frame set worth keeping, in bytes. Beyond this the cost
    /// of holding it outweighs a re-decode nobody is doing at drag speed.
    private static let maximumBytes = 96 * 1024 * 1024

    /// Held at all times, however big they are: the cell being worked on and the
    /// neighbours a user flicks between must survive their own arrival.
    private static let minimumEntries = 3

    /// Aggregate ceiling on resident decoded bytes (plan M6). The per-entry cap
    /// alone allowed capacity × 96 MB; eviction now also honours this total.
    private static let maximumTotalBytes = 192 * 1024 * 1024

    /// Cache key: path plus file size and mtime, so an overwritten file is a
    /// miss instead of stale pixels (plan M6 — the path-only key returned the
    /// old decode after the file changed on disk).
    private struct Key: Equatable {
        let path: String
        let size: UInt64
        let mtime: TimeInterval

        init(path: String) {
            self.path = path
            let attrs = try? FileManager.default.attributesOfItem(atPath: path)
            self.size = (attrs?[.size] as? UInt64) ?? 0
            self.mtime = (attrs?[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
        }
    }

    private var entries: [(key: Key, source: FrameSource)] = []

    private var totalBytes: Int {
        entries.reduce(0) { $0 + $1.source.pixelData.data.count }
    }

    /// Decodes in flight, by path.
    ///
    /// The decode itself runs off this actor — a detached task — and callers wait
    /// on its value. Two things follow, and both matter to a film preview whose
    /// cells all load at once. Sixteen different files decode *concurrently*
    /// rather than one behind another, which is what the actor's isolation used
    /// to impose: with the read and the decode inside `source(forPath:)`, every
    /// cell after the first queued behind a full JPEG 2000 decode, and a
    /// window/level drag — which needs nothing more than pixels already in hand —
    /// queued behind all of them. And sixteen cells of the *same* file share one
    /// decode rather than starting sixteen.
    private var loading: [String: Task<FrameSource?, Never>] = [:]

    /// Whether decoded frames are worth page-aligning on this machine.
    ///
    /// Resolved once: the backend cannot change during a run, and asking per file
    /// would probe the Metal device on the decode path.
    private static let alignsForGPU = FrameRenderService.shared.prefersAlignedPixelData

    /// The decoded source for a file, reading and decoding it if needed.
    ///
    /// Returns `nil` for anything that cannot be read or has no pixels — a
    /// report, a document, a corrupt file — and does not cache the failure: the
    /// caller has its own "this one failed" bookkeeping, and a file being
    /// written while it is read should not be poisoned forever.
    func source(forPath path: String) async -> FrameSource? {
        let key = Key(path: path)
        if let index = entries.firstIndex(where: { $0.key == key }) {
            // Most recently used last, so eviction takes the coldest.
            let entry = entries.remove(at: index)
            entries.append(entry)
            return entry.source
        }
        // Same path, different size/mtime: the file changed — drop stale pixels.
        entries.removeAll { $0.key.path == path }

        let task: Task<FrameSource?, Never>
        if let existing = loading[path] {
            task = existing
        } else {
            task = Task.detached(priority: .userInitiated) { Self.decode(path) }
            loading[path] = task
        }

        // Awaiting suspends this actor rather than holding it, so the next caller
        // gets in and starts its own decode instead of waiting out this one.
        let source = await task.value
        loading[path] = nil
        guard let source else { return nil }
        store(source, forKey: key)
        return source
    }

    /// Reads and decodes one file. Off the actor: this is the expensive part, and
    /// nothing about it needs exclusive access to the cache.
    private static func decode(_ path: String) -> FrameSource? {
        guard let data = FileManager.default.contents(atPath: path),
              let file = try? DICOMFile.read(from: data, force: true),
              let decoded = file.pixelData() else { return nil }

        // Page-align once, here, so every subsequent render can hand these bytes
        // straight to the GPU with `makeBuffer(bytesNoCopy:)` — no upload, ever.
        // The cost is one copy per *file*; the alternative is a copy of the same
        // size on every render, which for a mammogram is 23 MB per window delta.
        //
        // Only when the GPU is actually the active backend: on a CPU-only machine
        // the alignment buys nothing and the copy would be pure waste.
        let pixelData = alignsForGPU ? decoded.pageAligned() : decoded

        return FrameSource(
            file: file,
            pixelData: pixelData,
            paletteLUT: file.dataSet.paletteColorLUT())
    }

    /// Keeps a decoded file, evicting the coldest until the cache is inside its
    /// budget again.
    private func store(_ source: FrameSource, forKey key: Key) {
        let bytes = source.pixelData.data.count
        guard bytes <= Self.maximumBytes else { return }
        // A second caller can have stored the same file while this one decoded.
        guard !entries.contains(where: { $0.key == key }) else { return }

        entries.append((key, source))
        var total = entries.reduce(0) { $0 + $1.source.pixelData.data.count }
        while total > Self.budgetBytes, entries.count > Self.minimumEntries {
            total -= entries.removeFirst().source.pixelData.data.count
        }
        // Aggregate byte ceiling (plan M6): evict coldest until under budget,
        // even below the minimum-entries floor above.
        while totalBytes > Self.maximumTotalBytes, entries.count > 1 {
            entries.removeFirst()
        }
    }

    /// Forgets everything, e.g. when a study is closed.
    func clear() {
        entries.removeAll()
        for task in loading.values { task.cancel() }
        loading.removeAll()
    }
}
#endif
