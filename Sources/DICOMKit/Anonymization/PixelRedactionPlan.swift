// NEMA-verified: 2026a, checked 2026-09-29 — pixel redaction geometry only; Burned In Annotation per PS3.3 2026a C.7.6.1
import Foundation
import DICOMCore

/// Decides **which pixel regions to blank** to remove burned-in identifiers, and
/// records how that decision was reached.
///
/// ## Why this is a separate type
///
/// Region geometry deliberately does **not** live in ``ConfidentialityProfile/table``.
/// That table is a transcription of PS3.15 Table E.1-1 — a *tag* table, keyed by
/// attribute with an action code. Pixel redaction is keyed by *device and geometry*
/// and produces rectangles. fo-dicom's profile is auto-generated from the same
/// standard table, which structurally forecloses region rules; keeping the two
/// representations apart avoids inheriting that dead end.
///
/// ## The decision, in order
///
/// 1. **Caller-specified regions** — an explicit instruction always wins.
/// 2. **Keep-region inversion** — when the data set declares where the clinical
///    image is (Ultrasound Regions), blank everything *else*. Fail-safe: the
///    default is destruction, so undiscovered text outside the scan area goes too.
/// 3. **Device templates** — curated per Modality/Manufacturer/geometry.
/// 4. **Nothing applies** → ``Decision/unresolved``. Never a silent pass-through:
///    CTP's default (unmatched object forwarded unmodified, logged as success) is
///    the failure mode this type exists to avoid.
///
/// Strategies are *not* alternatives that override one another — a resolved plan may
/// union several sources. Detection may only ever **add** to the mask, never shrink it,
/// because a false positive costs blanked background while a false negative leaks PHI.
public struct PixelRedactionPlan: Sendable, Equatable {

    /// A rectangle to blank, in image pixels, origin top-left.
    public struct Region: Sendable, Hashable {
        public var x: Int
        public var y: Int
        public var width: Int
        public var height: Int

        public init(x: Int, y: Int, width: Int, height: Int) {
            self.x = x
            self.y = y
            self.width = width
            self.height = height
        }

        /// True when the two rectangles share at least one pixel.
        public func intersects(_ other: Region) -> Bool {
            other.x < x + width && x < other.x + other.width
                && other.y < y + height && y < other.y + other.height
        }

        /// True when `other` lies entirely inside this rectangle.
        public func covers(_ other: Region) -> Bool {
            other.x >= x && other.y >= y
                && other.x + other.width <= x + width
                && other.y + other.height <= y + height
        }
    }

    /// How the regions were arrived at — carried into the audit trail and the
    /// console, so an operator can see *why* these pixels were chosen.
    public enum Basis: String, Sendable, Equatable {
        /// The caller named the coordinates.
        case explicit
        /// Everything outside a region the data set itself declared as image content.
        case keepRegionInversion
        /// A curated template matched this device and geometry.
        case deviceTemplate
        /// On-device OCR (``TextRegionDetector``) found text at these coordinates.
        case textDetection
    }

    /// One contributing region source, kept so the audit trail can say *why* each
    /// rectangle exists when several sources were unioned.
    public struct Source: Sendable, Equatable {
        public let basis: Basis
        public let regions: [Region]
        public init(basis: Basis, regions: [Region]) {
            self.basis = basis
            self.regions = regions
        }
    }

    public enum Decision: Sendable, Equatable {
        /// Regions were determined; blanking may proceed.
        case redact(regions: [Region], basis: Basis)
        /// The image declares burned-in content (or carries overlays) but no strategy
        /// could locate it. The caller must refuse, not guess — `reason` explains.
        case unresolved(reason: String)
        /// Nothing suggests burned-in identifiers; no pixel work is required.
        case nothingToDo
    }

    public let decision: Decision

    /// Every source that contributed to a `.redact` decision, in precedence order. Empty
    /// for hand-built plans and non-redact decisions; `decision.basis` is `sources.first`.
    public let sources: [Source]

    public init(decision: Decision, sources: [Source] = []) {
        self.decision = decision
        self.sources = sources
    }

    // MARK: - Planning

    /// Builds a plan for one data set.
    ///
    /// - Parameters:
    ///   - dataSet: the source data set, **before** header de-identification. The
    ///     device templates key on Manufacturer / ManufacturerModelName / Modality,
    ///     which de-identification removes — so planning must happen first. CTP and
    ///     Presidio both document this same ordering dependency.
    ///   - explicitRegions: caller-supplied rectangles; when non-empty these are used
    ///     verbatim and no derivation is attempted.
    ///   - detectedRegions: OCR rectangles (redact verdicts only), unioned on top.
    ///   - blankOutsideDeclaredRegions: whether the keep-region inversion (everything
    ///     outside the declared Ultrasound Regions) contributes. `false` for the
    ///     `header` OCR mode, whose whole point is to keep scales and legends that the
    ///     vendor never declares as calibrated regions. Device templates still apply.
    ///   - textOnly: `--text-only` — NO automatic band at all: neither the keep-region
    ///     inversion nor a device template contributes. Only the caller's explicit
    ///     rectangles and the OCR verdicts blank pixels, so everything the classifier
    ///     kept (scanner settings, scales, legends) survives at its exact position.
    ///     The safety net is gone with it: text OCR missed is kept.
    public static func plan(
        for dataSet: DataSet,
        explicitRegions: [Region] = [],
        detectedRegions: [Region] = [],
        blankOutsideDeclaredRegions: Bool = true,
        textOnly: Bool = false
    ) -> PixelRedactionPlan {
        // Every enabled source may only ADD to the mask (principle: union, never
        // override). Explicit rectangles come first so they remain the recorded basis;
        // the derived strategies and OCR are unioned on top.
        var sources: [Source] = []
        if !explicitRegions.isEmpty {
            sources.append(Source(basis: .explicit, regions: explicitRegions))
        }

        let residual = ConfidentialityEngine.residualPixelPHIWarnings(in: dataSet)

        // Derive from a declared clinical region when the file offers one, else a
        // curated device template. These two are alternatives (the template describes
        // the same banner the declaration locates), so the first that resolves is used.
        // `textOnly` opts out of both: the operator asked for the flagged text and
        // nothing else.
        if textOnly {
            // No derived band; explicit rectangles and OCR below are the only sources.
        } else if blankOutsideDeclaredRegions, let inverted = keepRegionInversion(for: dataSet) {
            sources.append(Source(basis: .keepRegionInversion, regions: inverted))
        } else if var templated = DeviceRedactionTemplates.regions(for: dataSet) {
            // With the inversion off the declaration still protects the scan area: a
            // generic banner strip may not reach into the rows the declared clinical box
            // spans, or `header` mode would clip the sector apex — and the legend beside
            // it (colour-bar label, TI/MI readouts) — that the mode exists to preserve.
            // The banner is the rows ABOVE (and below) the scan area, full width.
            if !blankOutsideDeclaredRegions, let box = declaredRegionBoundingBox(for: dataSet),
               let columns = dataSet.uint16(for: .columns).map({ Int($0) }) {
                let scanRows = Region(x: 0, y: box.y, width: columns, height: box.height)
                templated = templated.flatMap { $0.subtracting(scanRows) }
            }
            if !templated.isEmpty {
                sources.append(Source(basis: .deviceTemplate, regions: templated))
            }
        }

        if !detectedRegions.isEmpty {
            sources.append(Source(basis: .textDetection, regions: detectedRegions))
        }

        if let primary = sources.first {
            return PixelRedactionPlan(
                decision: .redact(regions: unionedRegions(of: sources), basis: primary.basis),
                sources: sources)
        }

        // Nothing derived. If the image declares burned-in content, that is a refusal,
        // not a pass — otherwise there is genuinely nothing to do.
        if residual.isEmpty {
            return PixelRedactionPlan(decision: .nothingToDo)
        }
        return PixelRedactionPlan(decision: .unresolved(reason: residual.joined(separator: " ")))
    }

    /// The union of every source's rectangles, duplicates removed, order preserved.
    static func unionedRegions(of sources: [Source]) -> [Region] {
        var seen = Set<Region>()
        var out: [Region] = []
        for source in sources {
            for region in source.regions where seen.insert(region).inserted {
                out.append(region)
            }
        }
        return out
    }

    // MARK: - Keep-region inversion

    /// Everything *outside* the union of declared clinical regions.
    ///
    /// Ultrasound machines declare their scan geometry in Sequence of Ultrasound
    /// Regions (0018,6011) so measurements can be calibrated. That makes the
    /// complement of those rectangles the vendor's own statement of "not image
    /// content" — which is exactly where banners live. This is the one automatic,
    /// vendor-independent, fail-safe strategy available: blank all, restore declared.
    ///
    /// Note the honest limit: (0018,6011) delimits *calibrated measurement* regions,
    /// not a PHI boundary. It is a well-founded heuristic, not a conformance
    /// guarantee, and it only exists on ultrasound.
    static func keepRegionInversion(for dataSet: DataSet) -> [Region]? {
        guard let rows = dataSet.uint16(for: .rows).map({ Int($0) }), rows > 0,
              let columns = dataSet.uint16(for: .columns).map({ Int($0) }), columns > 0,
              let box = declaredRegionBoundingBox(for: dataSet)
        else { return nil }
        let minX = box.x, minY = box.y, maxX = box.x + box.width, maxY = box.y + box.height

        // A declared region covering the whole frame leaves nothing to blank — treat
        // that as "no usable declaration" rather than emitting zero regions, so the
        // caller falls through to templates instead of believing the image is clean.
        if minX == 0 && minY == 0 && maxX >= columns && maxY >= rows { return nil }

        // The four bands around the kept box, skipping empty ones.
        var regions: [Region] = []
        if minY > 0 {
            regions.append(Region(x: 0, y: 0, width: columns, height: minY))
        }
        if maxY < rows {
            regions.append(Region(x: 0, y: maxY, width: columns, height: rows - maxY))
        }
        if minX > 0 {
            regions.append(Region(x: 0, y: minY, width: minX, height: maxY - minY))
        }
        if maxX < columns {
            regions.append(Region(x: maxX, y: minY, width: columns - maxX, height: maxY - minY))
        }
        return regions.isEmpty ? nil : regions
    }

    /// Bounding box of every valid item in Sequence of Ultrasound Regions (0018,6011),
    /// or nil when the data set declares none. A bounding box (rather than per-region
    /// complements) keeps the arithmetic simple and errs toward keeping pixels between
    /// two declared regions — those lie inside the scan area.
    static func declaredRegionBoundingBox(for dataSet: DataSet) -> Region? {
        let declared = declaredRegions(for: dataSet)
        guard let first = declared.first else { return nil }
        var minX = first.x, minY = first.y, maxX = first.x + first.width, maxY = first.y + first.height
        for r in declared.dropFirst() {
            minX = min(minX, r.x); minY = min(minY, r.y)
            maxX = max(maxX, r.x + r.width); maxY = max(maxY, r.y + r.height)
        }
        return Region(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    /// Every valid item of Sequence of Ultrasound Regions (0018,6011) as a pixel
    /// rectangle — the vendor's own statement of where calibrated image content (and
    /// the scale drawn beside it) lives. Degenerate or out-of-range items are dropped
    /// rather than trusted; empty when the data set declares none.
    public static func declaredRegions(for dataSet: DataSet) -> [Region] {
        guard let rows = dataSet.uint16(for: .rows).map({ Int($0) }), rows > 0,
              let columns = dataSet.uint16(for: .columns).map({ Int($0) }), columns > 0,
              let items = dataSet.sequence(for: Tag(group: 0x0018, element: 0x6011))
        else { return [] }
        var out: [Region] = []
        for item in items {
            let set = DataSet(elements: item.allElements)
            guard let x0 = set.uint32(for: Tag(group: 0x0018, element: 0x6018)).map({ Int($0) }),
                  let y0 = set.uint32(for: Tag(group: 0x0018, element: 0x601A)).map({ Int($0) }),
                  let x1 = set.uint32(for: Tag(group: 0x0018, element: 0x601C)).map({ Int($0) }),
                  let y1 = set.uint32(for: Tag(group: 0x0018, element: 0x601E)).map({ Int($0) })
            else { continue }
            guard x1 > x0, y1 > y0, x0 >= 0, y0 >= 0, x1 <= columns, y1 <= rows else { continue }
            out.append(Region(x: x0, y: y0, width: x1 - x0, height: y1 - y0))
        }
        return out
    }
}

extension PixelRedactionPlan.Region {
    /// This rectangle minus `hole`: up to four rectangles (above, below, left, right of
    /// the overlap), none of them empty. The whole rectangle when they do not overlap;
    /// nothing when `hole` covers it.
    func subtracting(_ hole: PixelRedactionPlan.Region) -> [PixelRedactionPlan.Region] {
        let ix0 = max(x, hole.x), iy0 = max(y, hole.y)
        let ix1 = min(x + width, hole.x + hole.width), iy1 = min(y + height, hole.y + hole.height)
        guard ix1 > ix0, iy1 > iy0 else { return [self] }
        var out: [PixelRedactionPlan.Region] = []
        if iy0 > y { out.append(.init(x: x, y: y, width: width, height: iy0 - y)) }
        if iy1 < y + height { out.append(.init(x: x, y: iy1, width: width, height: y + height - iy1)) }
        if ix0 > x { out.append(.init(x: x, y: iy0, width: ix0 - x, height: iy1 - iy0)) }
        if ix1 < x + width { out.append(.init(x: ix1, y: iy0, width: x + width - ix1, height: iy1 - iy0)) }
        return out
    }
}
