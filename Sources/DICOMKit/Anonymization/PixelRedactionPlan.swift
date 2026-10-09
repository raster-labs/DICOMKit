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
    public struct Region: Sendable, Equatable {
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

    public init(decision: Decision) {
        self.decision = decision
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
    public static func plan(
        for dataSet: DataSet,
        explicitRegions: [Region] = []
    ) -> PixelRedactionPlan {
        if !explicitRegions.isEmpty {
            return PixelRedactionPlan(
                decision: .redact(regions: explicitRegions, basis: .explicit))
        }

        let residual = ConfidentialityEngine.residualPixelPHIWarnings(in: dataSet)

        // Derive from a declared clinical region when the file offers one.
        if let inverted = keepRegionInversion(for: dataSet) {
            return PixelRedactionPlan(
                decision: .redact(regions: inverted, basis: .keepRegionInversion))
        }

        // Curated device templates.
        if let templated = DeviceRedactionTemplates.regions(for: dataSet) {
            return PixelRedactionPlan(
                decision: .redact(regions: templated, basis: .deviceTemplate))
        }

        // Nothing derived. If the image declares burned-in content, that is a refusal,
        // not a pass — otherwise there is genuinely nothing to do.
        if residual.isEmpty {
            return PixelRedactionPlan(decision: .nothingToDo)
        }
        return PixelRedactionPlan(decision: .unresolved(reason: residual.joined(separator: " ")))
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
              let items = dataSet.sequence(for: Tag(group: 0x0018, element: 0x6011)),
              !items.isEmpty
        else { return nil }

        // Union of declared regions, as a bounding box. A bounding box (rather than
        // per-region complements) keeps the arithmetic simple and errs toward keeping
        // pixels between two declared regions — those lie inside the scan area.
        var minX = Int.max, minY = Int.max, maxX = Int.min, maxY = Int.min
        var found = 0
        for item in items {
            let set = DataSet(elements: item.allElements)
            guard let x0 = set.uint32(for: Tag(group: 0x0018, element: 0x6018)).map({ Int($0) }),
                  let y0 = set.uint32(for: Tag(group: 0x0018, element: 0x601A)).map({ Int($0) }),
                  let x1 = set.uint32(for: Tag(group: 0x0018, element: 0x601C)).map({ Int($0) }),
                  let y1 = set.uint32(for: Tag(group: 0x0018, element: 0x601E)).map({ Int($0) })
            else { continue }
            // Ignore degenerate or out-of-range declarations rather than trusting them.
            guard x1 > x0, y1 > y0, x0 >= 0, y0 >= 0, x1 <= columns, y1 <= rows else { continue }
            minX = min(minX, x0); minY = min(minY, y0)
            maxX = max(maxX, x1); maxY = max(maxY, y1)
            found += 1
        }
        guard found > 0 else { return nil }

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
}
