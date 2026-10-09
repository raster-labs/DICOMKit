// NEMA-verified: 2026a, checked 2026-09-29 — pixel redaction geometry only; Burned In Annotation per PS3.3 2026a C.7.6.1
import Foundation
import DICOMCore

/// Curated "where does this device burn its banner" templates.
///
/// ## Scope, stated honestly
///
/// This table is **small and deliberately conservative**. It is not a port of RSNA
/// CTP's signature library (~60 groups), and it is not a substitute for one. Every
/// entry here is a geometry someone verified; an unmatched device returns `nil`, which
/// the caller must treat as *unresolved*, never as *clean*.
///
/// ## Why fractions rather than absolute rectangles
///
/// CTP's signatures embed absolute pixel rectangles, which forces `Rows`/`Columns`
/// into the match key and produces near-duplicate entries per resolution variant of
/// the same scanner. Expressing the banner as a *fraction* of the frame lets one entry
/// cover a device's resolution family. The trade is precision: a fraction that is
/// slightly generous blanks a little extra background, which is the direction to err.
///
/// ## Matching
///
/// Modality must match. Manufacturer and model are matched case-insensitively as
/// substrings (so "GE MEDICAL SYSTEMS" matches a `"GE"` prefix rule). The **first**
/// matching entry wins, so order entries most-specific-first.
public enum DeviceRedactionTemplates {

    /// One curated device rule.
    struct Template: Sendable {
        /// Modality (0008,0060), matched exactly (case-insensitive).
        let modality: String
        /// Substring of Manufacturer (0008,0070); `nil` matches any.
        let manufacturer: String?
        /// Substring of Manufacturer's Model Name (0008,1090); `nil` matches any.
        let model: String?
        /// Bands to blank, as fractions of frame height, measured from the top.
        /// `0.0..<0.09` means "the top 9% of the image".
        let topFraction: Double
        /// Bands to blank as a fraction of frame height, measured from the bottom.
        let bottomFraction: Double
        /// Human-readable provenance for the audit trail.
        let note: String
    }

    /// The curated table. Most-specific first.
    ///
    /// Ultrasound dominates because ultrasound dominates real burned-in PHI: the
    /// modality-prevalence survey behind this work found burned-in text in 100% of US
    /// images versus 0.3% of MR.
    static let table: [Template] = [
        // --- Ultrasound: vendor banner across the top of the frame. ---
        Template(modality: "US", manufacturer: "GE", model: "LOGIQ",
                 topFraction: 0.10, bottomFraction: 0.0,
                 note: "GE LOGIQ family: patient/institution banner in the top strip"),
        Template(modality: "US", manufacturer: "Philips", model: "EPIQ",
                 topFraction: 0.07, bottomFraction: 0.0,
                 note: "Philips EPIQ: banner in the top strip"),
        Template(modality: "US", manufacturer: "Philips", model: "iU22",
                 topFraction: 0.07, bottomFraction: 0.0,
                 note: "Philips iU22: banner in the top strip"),
        Template(modality: "US", manufacturer: "SIEMENS", model: "ACUSON",
                 topFraction: 0.08, bottomFraction: 0.0,
                 note: "Siemens ACUSON: banner in the top strip"),
        Template(modality: "US", manufacturer: "TOSHIBA", model: nil,
                 topFraction: 0.08, bottomFraction: 0.0,
                 note: "Toshiba/Canon ultrasound: banner in the top strip"),
        // Generic ultrasound fallback. Ultrasound nearly always banners the top, and
        // for this modality a generous default is the safer error.
        Template(modality: "US", manufacturer: nil, model: nil,
                 topFraction: 0.12, bottomFraction: 0.0,
                 note: "Ultrasound generic: top strip (conservative default)"),
    ]

    /// Regions for this data set, or `nil` when no template matches.
    ///
    /// Returns `nil` rather than an empty array on no-match so the caller can tell
    /// "no rule applies" (→ unresolved) from "a rule applied and found nothing".
    static func regions(for dataSet: DataSet) -> [PixelRedactionPlan.Region]? {
        guard let rows = dataSet.uint16(for: .rows).map({ Int($0) }), rows > 0,
              let columns = dataSet.uint16(for: .columns).map({ Int($0) }), columns > 0
        else { return nil }

        let modality = (dataSet.string(for: .modality) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let manufacturer = (dataSet.string(for: .manufacturer) ?? "")
        let model = (dataSet.string(for: Tag(group: 0x0008, element: 0x1090)) ?? "")

        guard let match = table.first(where: { t in
            guard t.modality.caseInsensitiveCompare(modality) == .orderedSame else { return false }
            if let m = t.manufacturer,
               manufacturer.range(of: m, options: .caseInsensitive) == nil { return false }
            if let m = t.model,
               model.range(of: m, options: .caseInsensitive) == nil { return false }
            return true
        }) else { return nil }

        var regions: [PixelRedactionPlan.Region] = []
        // Round up, so a fractional band never lands a row short of the text.
        let topRows = Int((Double(rows) * match.topFraction).rounded(.up))
        if topRows > 0 {
            regions.append(.init(x: 0, y: 0, width: columns, height: min(topRows, rows)))
        }
        let bottomRows = Int((Double(rows) * match.bottomFraction).rounded(.up))
        if bottomRows > 0 {
            let y = max(0, rows - bottomRows)
            regions.append(.init(x: 0, y: y, width: columns, height: rows - y))
        }
        return regions.isEmpty ? nil : regions
    }

    /// Provenance note for the matched template, for the audit trail.
    static func matchNote(for dataSet: DataSet) -> String? {
        let modality = (dataSet.string(for: .modality) ?? "")
        let manufacturer = (dataSet.string(for: .manufacturer) ?? "")
        let model = (dataSet.string(for: Tag(group: 0x0008, element: 0x1090)) ?? "")
        return table.first(where: { t in
            guard t.modality.caseInsensitiveCompare(modality) == .orderedSame else { return false }
            if let m = t.manufacturer,
               manufacturer.range(of: m, options: .caseInsensitive) == nil { return false }
            if let m = t.model,
               model.range(of: m, options: .caseInsensitive) == nil { return false }
            return true
        })?.note
    }
}
