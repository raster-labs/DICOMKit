// NEMA-verified: 2026a, checked 2026-10-01 — C (Table E.1-1a) cleans text per E.3.5 instead of keeping it verbatim (D158); Modified Dates shifts DA and the DT date part by whole days, keeps TM, and gives the 3 non-date rows their Basic action (E.3.6, D157); (0028,0303) REMOVED / UNMODIFIED / MODIFIED per E.2 / E.3.6 and PS3.3 Table C.7-1 (D161); 113100 is the first Item of (0012,0064) and (0012,0063) names every Item, including 113101 from pixel cleaning (D160); Retain Safe Private keeps the Table E.3.10-1 attributes and (0008,0300) SAFE / Nonidentifying elements with their Private Creators and applies (0008,0307) D/Z/X/U (E.3.10), Clean Graphics cleans the text of a C sequence (E.3.3) (D159)
// NEMA-verified: 2026a, checked 2026-10-01 — Clean Structured Content (PS3.15 2026a E.3.4): the Items of Content Sequence (0040,A730), Acquisition Context Sequence (0040,0555) and Specimen Preparation Step Content Item Sequence (0040,0612) inside a cleaned (C) Sequence get the Table E.3.4-1 action of their Concept Name and Value Type (211 rows, retired SNOMED codes recognised): X removes the Content Item with its children, D replaces its value with a dummy of the Value Type, K keeps its value, C cleans its text or shifts its date (Modified Dates); the values removed join the text cleaner (D159)
// NEMA-verified: 2026a, checked 2026-09-30 — applies PS3.15 2026a Table E.1-1 in full (D69): the pattern rows (curve data 50xx, overlay data and comments 60xx,3000/4000, private groups) are X; Z on SQ is an empty sequence; D is a non-empty value consistent with the VR (sequence kept scrubbed, UID mapped, binary zero bytes) (PS3.15 E.1.1)
// NEMA-verified: 2026a, checked 2026-10-01 — Content Sequence (0040,A730) Basic Profile D without the Clean Structured Content Option (Table E.1-1 D, C only under the Option; E.1.1 "the action is applicable to the Sequence and all of its contents"): Content Items kept, Date/Time/DateTime/Person Name D and UID U by their own rows, and the values Table E.1-1 does not list (Text Value, NUM numeric values, TABLE cell values) replaced by dummies of the VR; Acquisition Context Sequence X/Z and Specimen Preparation Sequence Z unchanged (D236)
// NEMA-verified: 2026a, checked 2026-09-29 — applies the PS3.15 2026a Table E.1-1 actions; records (0012,0062) YES, (0012,0063) LO 1-n and (0012,0064) SQ of CID 7050 codes per PS3.15 E.1.1 and PS3.3 Table C.7-1; VRs per PS3.6 Table 6-1
import Foundation
import DICOMCore

/// Applies the PS3.15 Annex E Basic Application Level Confidentiality Profile to a
/// dataset — the standards-grounded de-identification path.
///
/// What it does that the legacy ``Anonymizer`` profiles do not:
/// 1. Applies Table E.1-1 **action codes** (D/Z/X/K/C/U) per attribute.
/// 2. **Recurses into every sequence item** so nested identifiers are scrubbed.
/// 3. **VR sweeps**: any PN not in the table is removed; any UI is regenerated
///    consistently (unless Retain UIDs); any private tag is removed (unless retained) —
///    so an attribute absent from the explicit table is never silently kept.
/// 4. Regenerates UIDs through one consistent map (same input UID → same output UID),
///    preserving referential integrity within the file.
/// 5. Records the de-identification method attributes (0012,0062)/(0012,0063)/(0012,0064)
///    as PS3.15 E.1.1 requires, with one CID 7050 code per profile/option applied.
///
/// **Scope: dataset only.** Pixel Data is never inspected or modified, so identifiers
/// burned into the image (and identifying overlay planes) survive a pass. When such
/// residual PHI is declared, (0012,0062) is set to NO rather than YES and the caller is
/// warned — see ``deidentifyReportingResidualPHI(_:)``.
///
/// It is a value type driven by ``ConfidentialityProfile/Options``; the caller owns the
/// UID map so it can be shared across a study for cross-file consistency.
public struct ConfidentialityEngine {

    public let options: ConfidentialityProfile.Options

    /// Shared input-UID → output-UID map. Injected so multiple files in one study
    /// regenerate the same UIDs identically. Defaults to a fresh empty map.
    public var uidMap: [String: String]

    /// UIDs that identify the SOP class / transfer syntax etc. and must NOT be
    /// regenerated — doing so would corrupt the object. (PS3.15 E.1: only instance
    /// UIDs are remapped, not the well-known class UIDs.)
    private static let preservedUIDTags: Set<Tag> = [
        Tag(group: 0x0002, element: 0x0002), // Media Storage SOP Class UID
        Tag(group: 0x0002, element: 0x0010), // Transfer Syntax UID
        Tag(group: 0x0002, element: 0x0012), // Implementation Class UID
        .init(group: 0x0008, element: 0x0016), // SOP Class UID
    ]

    /// The values the profile removes or replaces in the data set being de-identified,
    /// found before any change; the Clean ("C") action removes them from the text it keeps
    /// (PS3.15 2026a E.3.5, D158).
    private var identifyingValues: DescriptorCleaner = DescriptorCleaner(values: [])

    /// Private Data Element Characteristics Sequence (0008,0300) of the data set being
    /// de-identified, read before any change (Retain Safe Private Option, E.3.10).
    private var privateDeclarations: [String: PrivateBlockDeclaration] = [:]

    public init(options: ConfidentialityProfile.Options = .basic,
                uidMap: [String: String] = [:]) {
        self.options = options
        self.uidMap = uidMap
    }

    /// One de-identification pass. Returns the scrubbed dataset and the list of tags
    /// that changed (top level only, for reporting). `uidMap` is updated in place.
    public mutating func deidentify(_ dataSet: DataSet) -> (DataSet, [Tag]) {
        let (result, changed, _) = deidentifyReportingResidualPHI(dataSet)
        return (result, changed)
    }

    /// One de-identification pass that also reports **residual PHI this engine cannot
    /// remove** — identifiers rendered into the pixels or carried in overlay planes.
    ///
    /// This engine scrubs the *dataset only*; it never inspects or rewrites Pixel Data
    /// (see the skip in ``apply(to:changed:isRoot:)``). So on an image whose pixels carry
    /// a burned-in patient banner, a metadata-only pass produces a file that is **not**
    /// de-identified. PS3.15 conditions (0012,0062) Patient Identity Removed = YES on the
    /// whole object being clean, so asserting YES there would be a false claim — the most
    /// dangerous possible output, because downstream consumers trust that tag.
    ///
    /// When residual PHI is detected this pass therefore: (a) records (0012,0062) as
    /// **NO** instead of YES, noting the metadata-only scope in (0012,0063), and
    /// (b) returns a warning naming the cause. Callers should surface the warning and
    /// treat the file as still-identifiable. The metadata scrub still happens in full —
    /// this reports the limit, it does not skip the work.
    ///
    /// - Returns: the scrubbed dataset, the changed top-level tags, and any residual-PHI
    ///   warnings (empty when the object is clean as far as this engine can tell).
    public mutating func deidentifyReportingResidualPHI(
        _ dataSet: DataSet
    ) -> (DataSet, [Tag], [String]) {
        let residual = Self.residualPixelPHIWarnings(in: dataSet)
        privateDeclarations = options.retainSafePrivate ? Self.privateBlockDeclarations(in: dataSet) : [:]
        identifyingValues = DescriptorCleaner(values: removedValues(in: dataSet))
        var changed: [Tag] = []
        var result = apply(to: dataSet, changed: &changed, isRoot: true)
        recordMethod(in: &result, pixelsMayCarryPHI: !residual.isEmpty)
        return (result, changed, residual)
    }

    // MARK: - Residual (pixel-borne) PHI detection

    /// Reasons the *pixels* of this object may still identify the patient after a
    /// metadata-only pass. Detection is by declared attribute, not by reading pixels:
    /// we do not OCR the image, so this is a conservative flag, never a guarantee.
    public static func residualPixelPHIWarnings(in dataSet: DataSet) -> [String] {
        var warnings: [String] = []

        // (0028,0301) Burned In Annotation — the modality's own declaration that
        // identifying text is rendered into the pixels.
        if let burned = dataSet.string(for: .burnedInAnnotation)?
            .trimmingCharacters(in: .whitespacesAndNewlines).uppercased(),
           burned == "YES" {
            warnings.append(
                "Burned In Annotation (0028,0301) is YES: identifying text is rendered "
                + "into the pixel data, which a metadata-only pass leaves untouched. The "
                + "image is NOT de-identified; (0012,0062) is therefore recorded as NO. "
                + "Clean the pixels (PS3.15 Clean Pixel Data Option) before release.")
        }

        // Overlay planes (60xx,3000) can carry identifying graphics/text that renderers
        // burn into the displayed image — a second route to the same leak. Groups run
        // 0x6000…0x601E, even only (PS3.3 C.9).
        var overlayGroups: [String] = []
        for group in stride(from: UInt16(0x6000), through: UInt16(0x601E), by: 2)
        where dataSet[Tag(group: group, element: 0x3000)] != nil {
            overlayGroups.append(String(format: "%04X", group))
        }
        if !overlayGroups.isEmpty {
            warnings.append(
                "Overlay plane data present (\(overlayGroups.joined(separator: ", "))): "
                + "overlays are burned into the rendered image and are not modified by "
                + "this profile. Review them for identifying content before release.")
        }

        return warnings
    }

    // MARK: - Recursive application

    private mutating func apply(to dataSet: DataSet, changed: inout [Tag], isRoot: Bool,
                                cleaning: Bool = false) -> DataSet {
        var out = dataSet
        // Retain Safe Private Option: the private blocks of this Data Set (Items do not
        // inherit the reservations of the enclosing Data Set, PS3.5 7.8.1) (D159).
        let privateActions = options.retainSafePrivate ? safePrivateActions(in: dataSet) : [:]

        for tag in dataSet.tags {
            guard let element = dataSet[tag] else { continue }

            // Never touch Pixel Data or the group-length/meta plumbing.
            if tag == .pixelData || tag.group == 0x0002 { continue }

            let effective = effectiveAction(for: tag, element: element, cleaning: cleaning,
                                            privateActions: privateActions)

            // Recurse into sequences first (nested identifiers), keeping the element.
            if let items = element.sequenceItems {
                let innerCleaning = cleaning || effective == .clean
                // Clean Structured Content (PS3.15 E.3.4): the Items of a cleaned Sequence of
                // Content Items get the Table E.3.4-1 action of their Concept Name (D159).
                let contentItems = options.cleanStructuredContent && innerCleaning
                    && Self.contentItemSequences.contains(tag)
                // Basic Profile D on Content Sequence (0040,A730) without the Option: the D
                // reaches the Content Items' values Table E.1-1 does not list (D236).
                let dummyContentItems = effective == .replaceDummy && Self.contentItemSequences.contains(tag)
                let scrubbedItems = items.compactMap { item -> SequenceItem? in
                    let itemAction = contentItems
                        ? ConfidentialityProfile.contentItemAction(for: item, options: options) : nil
                    if itemAction == .remove || itemAction == .removePreferred { return nil }
                    var itemSet = DataSet(elements: item.allElements)
                    var inner: [Tag] = []
                    itemSet = apply(to: itemSet, changed: &inner, isRoot: false, cleaning: innerCleaning)
                    if let itemAction {
                        applyContentItemAction(itemAction, original: DataSet(elements: item.allElements), to: &itemSet)
                    }
                    if dummyContentItems { Self.replaceUnlistedContentItemValues(in: &itemSet) }
                    return SequenceItem(elements: itemSet.tags.compactMap { itemSet[$0] })
                }
                out.setSequence(scrubbedItems, for: tag)
                // Fall through: the sequence attribute itself may also be listed in
                // the table (e.g. Referring Physician ID Sequence → X).
            }

            guard let action = effective else { continue }

            switch action {
            case .keep:
                continue
            case .remove, .removePreferred:
                out.remove(tag: tag)
                if isRoot { changed.append(tag) }
            case .zero:
                Self.setZeroLength(tag, vr: element.vr, in: &out)
                if isRoot { changed.append(tag) }
            case .zeroOrDummy:
                if modifyDate(tag: tag, element: element, in: &out, changed: &changed, isRoot: isRoot) {
                    continue
                }
                Self.setZeroLength(tag, vr: element.vr, in: &out)
                if isRoot { changed.append(tag) }
            case .replaceDummy:
                // A non-zero-length value "consistent with the VR" (PS3.15 E.1.1, D):
                // a sequence keeps its items, already scrubbed above (a Sequence of Content
                // Items with the values Table E.1-1 does not list replaced, D236); a UID is replaced
                // by its consistently mapped UID; binary VRs get zero bytes.
                switch element.vr {
                case .SQ:
                    break
                case .UI:
                    if let uid = dataSet.string(for: tag) {
                        out.setString(mappedUID(uid), for: tag, vr: .UI)
                    }
                case .OB, .OD, .OF, .OL, .OV, .OW, .UN, .US, .SS, .UL, .SL, .FL, .FD, .AT, .SV, .UV:
                    out[tag] = DataElement.data(tag: tag, vr: element.vr,
                                                data: Data(repeating: 0, count: Self.binaryDummyLength(element.vr)))
                default:
                    out.setString(dummyValue(for: element.vr), for: tag, vr: element.vr)
                }
                if isRoot { changed.append(tag) }
            case .clean:
                // C: keep the value with the identifying information removed (PS3.15
                // 2026a Table E.1-1a; E.3.5 for descriptors). Text is cleaned by
                // ``DescriptorCleaner``; a sequence keeps its Items, already processed
                // above, with the text in them cleaned the same way; any other VR cannot
                // be cleaned and is made zero-length (D158).
                if element.vr == .SQ {
                    let items = out.sequence(for: tag) ?? []
                    let cleaned = items.map(cleanText(in:))
                    if !Self.sameItems(cleaned, items) { out.setSequence(cleaned, for: tag) }
                    // Reported when the Items differ from the source (removed Content Items
                    // and dummy values included), not only when the text cleaning changed them.
                    if isRoot, !Self.sameItems(cleaned, element.sequenceItems ?? []) { changed.append(tag) }
                    continue
                }
                if Self.cleanableVRs.contains(element.vr) {
                    if let cleaned = cleanedText(of: out[tag] ?? element) {
                        out[tag] = cleaned
                        if isRoot { changed.append(tag) }
                    }
                    continue
                }
                Self.setZeroLength(tag, vr: element.vr, in: &out)
                if isRoot { changed.append(tag) }
            case .replaceUID:
                if let uid = dataSet.string(for: tag) {
                    out.setString(mappedUID(uid), for: tag, vr: element.vr)
                    if isRoot { changed.append(tag) }
                }
            }
        }

        return out
    }

    /// The action `apply` takes for an element: ``resolveAction(for:vr:isPrivate:)``, then
    /// the Retain Safe Private decisions and the cleaning of descriptors inside a cleaned
    /// Sequence.
    private func effectiveAction(for tag: Tag, element: DataElement, cleaning: Bool,
                                 privateActions: [Tag: ConfidentialityProfile.Action]) -> ConfidentialityProfile.Action? {
        var effective = resolveAction(for: tag, vr: element.vr, isPrivate: tag.isOddGroup)  // PS3.5 7.8.1: groups 0001-0007/FFFF go too
        // Retain Safe Private (PS3.15 E.3.10): a safe Private Attribute and the Private
        // Creator it needs are kept; one with a Deidentification Action (0008,0307) gets
        // that action; a private Sequence is kept with its Items processed; the rest go.
        if options.retainSafePrivate, tag.isPrivate {
            effective = privateActions[tag] ?? .remove
        }
        // Inside a Sequence that is cleaned (C), a descriptor (a row with a Clean
        // Descriptors "C") is cleaned rather than replaced, so Clean Graphics keeps the
        // text of a Graphic Annotation with the identifying information taken out
        // (PS3.15 E.3.3) (D159).
        if cleaning, let current = effective, current != .keep,
           ConfidentialityProfile.tableE11[UInt32(tag.group) << 16 | UInt32(tag.element)]?.cleanDescriptors == "C" {
            effective = .clean
        }
        return effective
    }

    /// Combines the explicit table, VR sweeps and the private-tag rule.
    private func resolveAction(for tag: Tag, vr: VR, isPrivate: Bool) -> ConfidentialityProfile.Action? {
        // 1. Explicit table wins.
        if let a = ConfidentialityProfile.action(for: tag, options: options) {
            // The table encodes UID rows generically; honour Retain UIDs here.
            if a == .replaceUID && options.retainUIDs { return .keep }
            return a
        }

        // 2. The pattern rows of Table E.1-1, all X in the Basic Profile: Curve Data
        //    (50xx,xxxx), Overlay Data (60xx,3000) and Overlay Comments (60xx,4000) (D69).
        if tag.group & 0xFF00 == 0x5000 && tag.group % 2 == 0 { return .remove }
        if tag.group & 0xFF00 == 0x6000 && tag.group % 2 == 0,
           tag.element == 0x3000 || tag.element == 0x4000 { return .remove }

        // 2b. Private tags: remove unless the whole private-retention isn't modelled
        //    (PS3.15 only retains private tags a creator has declared safe; we have no
        //    safe-private registry, so remove — the conservative, conformant default).
        if isPrivate { return .remove }

        // 3. VR sweeps for attributes not otherwise listed.
        switch vr {
        case .PN:
            // Any residual person name is an identifier — remove.
            return .remove
        case .UI where !Self.isPreservedUID(tag):
            return options.retainUIDs ? .keep : .replaceUID
        default:
            return nil   // keep
        }
    }

    private static func isPreservedUID(_ tag: Tag) -> Bool {
        preservedUIDTags.contains(tag)
    }

    // MARK: - Value helpers

    /// Retain Longitudinal Temporal Information With Modified Dates (PS3.15 2026a E.3.6,
    /// D157): the dates and times of the rows with a Modified Dates entry are modified by
    /// one whole-day offset, which keeps every interval between them. DA values and the
    /// date part of DT values are shifted (a DT's time and UTC offset are kept); a TM is
    /// the time of day of a shifted date, so it is kept as it is. A row of another VR
    /// (Timezone Offset From UTC, the OB timestamps) cannot be shifted and gets its Basic
    /// Profile action. A value that cannot be parsed is made zero-length.
    ///
    /// Returns false when the option is not in force for this row (the caller applies Z).
    private mutating func modifyDate(tag: Tag, element: DataElement, in dataSet: inout DataSet,
                                     changed: inout [Tag], isRoot: Bool) -> Bool {
        guard options.retainLongitudinalTemporal, let days = options.dateOffsetDays,
              let row = ConfidentialityProfile.tableE11[UInt32(tag.group) << 16 | UInt32(tag.element)],
              row.modifiedDates != nil else { return false }
        let original = dataSet.string(for: tag)
        switch element.vr {
        case .TM:
            return true  // kept: the time of day of a date shifted by whole days
        case .DA, .DT:
            let values = (original ?? "").components(separatedBy: "\\")
            let shifted = values.map { value -> String? in
                let v = value.trimmingCharacters(in: .whitespaces)
                if v.isEmpty { return "" }
                return element.vr == .DA ? Self.shiftDICOMDate(v, byDays: days)
                                         : Self.shiftDICOMDateTime(v, byDays: days)
            }
            if shifted.contains(where: { $0 == nil }) {
                Self.setZeroLength(tag, vr: element.vr, in: &dataSet)
            } else {
                dataSet.setString(shifted.map { $0! }.joined(separator: "\\"), for: tag, vr: element.vr)
            }
        default:
            switch ConfidentialityProfile.basicAction(row.basic) {
            case .remove, .removePreferred:
                dataSet.remove(tag: tag)
            case .replaceDummy:
                if Self.binaryVRs.contains(element.vr) {
                    dataSet[tag] = DataElement.data(tag: tag, vr: element.vr,
                                                    data: Data(repeating: 0, count: Self.binaryDummyLength(element.vr)))
                } else {
                    dataSet.setString(dummyValue(for: element.vr), for: tag, vr: element.vr)
                }
            default:
                Self.setZeroLength(tag, vr: element.vr, in: &dataSet)
            }
        }
        if isRoot { changed.append(tag) }
        return true
    }

    /// The element with its text cleaned, or nil when cleaning changes nothing.
    private func cleanedText(of element: DataElement) -> DataElement? {
        guard Self.cleanableVRs.contains(element.vr), let text = element.stringValue else { return nil }
        let values = Self.singleValuedVRs.contains(element.vr) ? [text] : text.components(separatedBy: "\\")
        let cleaned = values.map { identifyingValues.clean($0) }
        guard cleaned != values else { return nil }
        return DataElement.string(tag: element.tag, vr: element.vr, value: cleaned.joined(separator: "\\"))
    }

    /// An Item with the text of every element cleaned, at any depth.
    private func cleanText(in item: SequenceItem) -> SequenceItem {
        SequenceItem(elements: item.allElements.map { element -> DataElement in
            if let items = element.sequenceItems {
                var holder = DataSet()
                holder.setSequence(items.map(cleanText(in:)), for: element.tag)
                return holder[element.tag] ?? element
            }
            return cleanedText(of: element) ?? element
        })
    }

    private static func sameItems(_ a: [SequenceItem], _ b: [SequenceItem]) -> Bool {
        guard a.count == b.count else { return false }
        for (x, y) in zip(a, b) {
            let ex = x.allElements, ey = y.allElements
            guard ex.count == ey.count else { return false }
            for (p, q) in zip(ex, ey) {
                guard p.tag == q.tag, p.vr == q.vr else { return false }
                if let ip = p.sequenceItems, let iq = q.sequenceItems {
                    if !sameItems(ip, iq) { return false }
                } else if p.valueData != q.valueData {
                    return false
                }
            }
        }
        return true
    }

    // MARK: - Clean Structured Content Option (PS3.15 2026a E.3.4, D159)

    /// Sequences whose Items are Content Items (PS3.3 2026a Table C.17-6 Document Relationship
    /// Macro, Table 10-2 Content Item Macro): the Content Sequence of an SR document and of a
    /// Content Item, Acquisition
    /// Context Sequence, and Specimen Preparation Step Content Item Sequence (the Items of
    /// Specimen Preparation Sequence) (PS3.15 2026a E.3.4).
    static let contentItemSequences: Set<Tag> = [
        .contentSequence,                       // (0040,A730)
        Tag(group: 0x0040, element: 0x0555),    // Acquisition Context Sequence
        Tag(group: 0x0040, element: 0x0612),    // Specimen Preparation Step Content Item Sequence
    ]

    /// The attributes that hold a Content Item's value, by Value Type (PS3.3 2026a Table C.17-5
    /// Document Content Macro, Table 10-2 Content Item Macro, Table C.18.1-1): what Table E.3.4-1 acts on when it keeps (K), cleans (C) or replaces (D)
    /// the value of a Content Item.
    static func contentItemValueTags(valueType: String) -> [Tag] {
        switch valueType {
        case "TEXT": return [.textValue]
        case "DATE": return [Tag(group: 0x0040, element: 0xA121)]
        case "TIME": return [Tag(group: 0x0040, element: 0xA122)]
        case "DATETIME": return [Tag(group: 0x0040, element: 0xA120)]
        case "PNAME": return [.personName]
        case "UIDREF": return [Tag(group: 0x0040, element: 0xA124)]
        case "NUM":  // SR: Measured Value Sequence (Table C.18.1-1); Content Item Macro: the values themselves
            return [Tag(group: 0x0040, element: 0xA300), Tag(group: 0x0040, element: 0xA301),
                    Tag(group: 0x0040, element: 0xA30A), Tag(group: 0x0040, element: 0xA161),
                    Tag(group: 0x0040, element: 0xA162), Tag(group: 0x0040, element: 0xA163),
                    Tag(group: 0x0040, element: 0x08EA)]
        case "CODE": return [Tag(group: 0x0040, element: 0xA168)]
        case "IMAGE", "COMPOSITE", "WAVEFORM": return [.referencedSOPSequence]
        default: return []
        }
    }

    // MARK: - Basic Profile D on Content Sequence (PS3.15 2026a Table E.1-1, D236)

    /// Measured Value Sequence (0040,A300) (PS3.3 2026a Table C.18.1-1).
    static let measuredValueSequence = Tag(group: 0x0040, element: 0xA300)
    /// Tabulated Values Sequence (0040,A801) (PS3.3 2026a Table C.18.10-1).
    static let tabulatedValuesSequence = Tag(group: 0x0040, element: 0xA801)
    /// Cell Values Sequence (0040,A808) (PS3.3 2026a Table C.18.10-1).
    static let cellValuesSequence = Tag(group: 0x0040, element: 0xA808)
    /// The numeric value attributes of a NUM Content Item (Table C.18.1-1, Table 10-2): Numeric
    /// Value (0040,A30A), Floating Point Value (0040,A161), Rational Numerator Value (0040,A162);
    /// Rational Denominator Value (0040,A163) is handled apart (it must stay non-zero).
    static let numericValueTags: [Tag] = [Tag(group: 0x0040, element: 0xA30A),
                                          Tag(group: 0x0040, element: 0xA161),
                                          Tag(group: 0x0040, element: 0xA162)]
    static let rationalDenominatorValue = Tag(group: 0x0040, element: 0xA163)
    /// Selector Attribute VR (0072,0050): names the VR of a table cell; not a value.
    static let selectorAttributeVR = Tag(group: 0x0072, element: 0x0050)

    /// PS3.15 2026a Table E.1-1 gives Content Sequence (0040,A730) the Basic Profile action D
    /// ("replace with a non-zero length value that may be a dummy value and consistent with
    /// the VR", Table E.1-1a), and E.1.1: "in the case of Sequences, the action is applicable
    /// to the Sequence and all of its contents". The Content Items themselves are kept (a
    /// non-zero length Sequence, with the Relationship Type, Value Type, Concept Name and
    /// references the SR IOD requires, E.1.1 "does not negatively affect the integrity of the
    /// Information Object Definition"), the Content Item attributes that have their own Table
    /// E.1-1 row get that row's action (Date, Time, DateTime, Person Name D; UID U), and the
    /// value attributes Table E.1-1 does not list get a dummy value of their VR here:
    /// - TEXT: Text Value (0040,A160);
    /// - NUM: Numeric Value, Floating Point Value, Rational Numerator Value 0 and Rational
    ///   Denominator Value 1, in the Item and in its Measured Value Sequence Items;
    /// - TABLE: the Selector <VR> Value of each Cell Values Sequence Item.
    /// Each value of a multi-valued attribute is replaced, so the number of values is kept.
    /// Coded values (Concept Code Sequence) are kept: "it is usually safe to assume that coded
    /// sequence entries … do not contain identifying information" (E.1.1). The Clean
    /// Structured Content Option replaces this D with C (E.3.4, Table E.3.4-1).
    static func replaceUnlistedContentItemValues(in item: inout DataSet) {
        if let text = item[.textValue] { item[.textValue] = dummyElement(text) }
        replaceNumericValues(in: &item)
        if let measured = item.sequence(for: measuredValueSequence) {
            item.setSequence(measured.map { value in
                var ds = DataSet(elements: value.allElements)
                replaceNumericValues(in: &ds)
                return SequenceItem(elements: ds.tags.compactMap { ds[$0] })
            }, for: measuredValueSequence)
        }
        if let tables = item.sequence(for: tabulatedValuesSequence) {
            item.setSequence(tables.map { table in
                var ds = DataSet(elements: table.allElements)
                if let cells = ds.sequence(for: cellValuesSequence) {
                    ds.setSequence(cells.map { cell in
                        var c = DataSet(elements: cell.allElements)
                        for tag in c.tags where tag.group == 0x0072 && tag != selectorAttributeVR {
                            if let e = c[tag], e.sequenceItems == nil { c[tag] = dummyElement(e) }
                        }
                        return SequenceItem(elements: c.tags.compactMap { c[$0] })
                    }, for: cellValuesSequence)
                }
                return SequenceItem(elements: ds.tags.compactMap { ds[$0] })
            }, for: tabulatedValuesSequence)
        }
    }

    private static func replaceNumericValues(in ds: inout DataSet) {
        for tag in numericValueTags {
            if let e = ds[tag] { ds[tag] = dummyElement(e) }
        }
        if let e = ds[rationalDenominatorValue] {
            let count = max(1, e.valueData.count / 4)
            var one = Data()
            for _ in 0..<count { one.append(contentsOf: [1, 0, 0, 0]) }  // UL 1, little endian
            ds[rationalDenominatorValue] = DataElement.data(tag: e.tag, vr: e.vr, data: one)
        }
    }

    /// A dummy value consistent with the VR, with as many values as the source: zero bytes of
    /// the same length for a binary VR, ``dummyString(for:)`` for each value of a string VR.
    private static func dummyElement(_ e: DataElement) -> DataElement {
        if binaryVRs.contains(e.vr) {
            let count = max(e.valueData.count, binaryDummyLength(e.vr))
            return DataElement.data(tag: e.tag, vr: e.vr, data: Data(repeating: 0, count: count))
        }
        let values = singleValuedVRs.contains(e.vr) ? [e.stringValue ?? ""]
                                                     : (e.stringValue ?? "").components(separatedBy: "\\")
        let dummy = dummyString(for: e.vr)
        return DataElement.string(tag: e.tag, vr: e.vr, value: values.map { _ in dummy }.joined(separator: "\\"))
    }

    /// Applies a Content Item's Table E.3.4-1 action (not X, which drops the Item) to the
    /// Item after Table E.1-1 has processed its attributes:
    /// - K: its value attributes are kept as they were in the source;
    /// - C: TEXT cleaned (E.3.5 manner, ``DescriptorCleaner``); DATE and DATETIME shifted by
    ///   the Modified Dates offset; TIME kept (the time of day of a date shifted by whole days);
    /// - D (Z, Z/D): TEXT, DATE, TIME, DATETIME and PNAME get a dummy value of the VR, UIDREF a
    ///   UID mapped consistently; a reference (IMAGE, COMPOSITE, WAVEFORM) keeps its Referenced
    ///   SOP Sequence with the UIDs Table E.1-1 replaces (U) replaced.
    private mutating func applyContentItemAction(_ action: ConfidentialityProfile.Action,
                                                 original: DataSet, to item: inout DataSet) {
        let valueType = original.string(for: .valueType)?.trimmingCharacters(in: .whitespaces).uppercased() ?? ""
        for tag in Self.contentItemValueTags(valueType: valueType) {
            guard let source = original[tag] else { continue }
            switch action {
            case .keep:
                item[tag] = source
            case .clean:
                switch valueType {
                case "TEXT":
                    item[tag] = cleanedText(of: source) ?? source
                case "DATE", "DATETIME":
                    guard let days = options.dateOffsetDays, let value = original.string(for: tag) else {
                        item[tag] = source
                        continue
                    }
                    let shifted = valueType == "DATE" ? Self.shiftDICOMDate(value, byDays: days)
                                                      : Self.shiftDICOMDateTime(value, byDays: days)
                    if let shifted { item.setString(shifted, for: tag, vr: source.vr) }
                    else { Self.setZeroLength(tag, vr: source.vr, in: &item) }
                default:
                    item[tag] = source
                }
            case .replaceDummy, .zero, .zeroOrDummy:
                switch source.vr {
                case .UI:
                    if let uid = original.string(for: tag) { item.setString(mappedUID(uid), for: tag, vr: .UI) }
                case .SQ:
                    break  // a reference: its Items were processed by Table E.1-1 (UIDs replaced)
                default:
                    item.setString(dummyValue(for: source.vr), for: tag, vr: source.vr)
                }
            case .replaceUID:
                if let uid = original.string(for: tag), source.vr == .UI {
                    item.setString(mappedUID(uid), for: tag, vr: .UI)
                }
            case .remove, .removePreferred:
                break  // the caller drops the Item
            }
        }
    }

    /// The text, name, date and UID values of a Content Item (and, when `recursive`, of the
    /// Content Items below it), for the text cleaner: values a Content Item removed or
    /// replaced by the Clean Structured Content Option are removed from the text kept.
    static func contentItemValues(in item: SequenceItem, recursive: Bool) -> [(String, VR)] {
        var out: [(String, VR)] = []
        let ds = DataSet(elements: item.allElements)
        let valueType = ds.string(for: .valueType)?.trimmingCharacters(in: .whitespaces).uppercased() ?? ""
        for tag in contentItemValueTags(valueType: valueType) {
            guard let element = ds[tag], element.vr != .SQ, let value = ds.string(for: tag) else { continue }
            let values = singleValuedVRs.contains(element.vr) ? [value] : value.components(separatedBy: "\\")
            out += values.map { ($0, element.vr) }
        }
        if recursive {
            for child in ds.sequence(for: .contentSequence) ?? [] {
                out += contentItemValues(in: child, recursive: true)
            }
        }
        return out
    }

    // MARK: - Retain Safe Private Option (PS3.15 2026a E.3.10, D159)

    /// A private block's declaration in Private Data Element Characteristics Sequence
    /// (0008,0300) (PS3.3 2026a Table C.12-1).
    struct PrivateBlockDeclaration {
        /// Block Identifying Information Status (0008,0303): SAFE, UNSAFE or MIXED.
        var status: String
        /// Nonidentifying Private Elements (0008,0304): elements (00-FF) within the block.
        var nonidentifying: Set<UInt16>
        /// Deidentification Action (0008,0307) per element of Identifying Private Elements (0008,0306).
        var actions: [UInt16: String]
    }

    /// The (0008,0300) declarations, keyed "<group hex>|<Private Creator>".
    static func privateBlockDeclarations(in dataSet: DataSet) -> [String: PrivateBlockDeclaration] {
        var out: [String: PrivateBlockDeclaration] = [:]
        for item in dataSet.sequence(for: Tag(group: 0x0008, element: 0x0300)) ?? [] {
            let ds = DataSet(elements: item.allElements)
            guard let group = ds.uint16(for: Tag(group: 0x0008, element: 0x0301)),
                  let creator = ds.string(for: Tag(group: 0x0008, element: 0x0302))?
                    .trimmingCharacters(in: .whitespaces) else { continue }
            var declaration = PrivateBlockDeclaration(
                status: ds.string(for: Tag(group: 0x0008, element: 0x0303))?
                    .trimmingCharacters(in: .whitespaces).uppercased() ?? "",
                nonidentifying: Set(ds[Tag(group: 0x0008, element: 0x0304)]?.uint16Values ?? []),
                actions: [:])
            for actionItem in ds.sequence(for: Tag(group: 0x0008, element: 0x0305)) ?? [] {
                let a = DataSet(elements: actionItem.allElements)
                guard let code = a.string(for: Tag(group: 0x0008, element: 0x0307))?
                        .trimmingCharacters(in: .whitespaces).uppercased() else { continue }
                for element in a[Tag(group: 0x0008, element: 0x0306)]?.uint16Values ?? [] {
                    declaration.actions[element] = code
                }
            }
            out[String(format: "%04X|", group) + creator] = declaration
        }
        return out
    }

    /// The action for each Private Data Element and Private Creator of one Data Set under
    /// the Retain Safe Private Option. Safe: listed in Table E.3.10-1 for its Private
    /// Creator, or declared SAFE / Nonidentifying in (0008,0300). A Deidentification
    /// Action (0008,0307) D, Z, X or U is applied as given. A private Sequence that is not
    /// known safe is kept and its Items processed ("parsed in its entirety"). A Private
    /// Creator is kept when its block keeps an element (E.3.10: "together with the Private
    /// Creator IDs that are required"). Absent from the result: removed.
    private func safePrivateActions(in dataSet: DataSet) -> [Tag: ConfidentialityProfile.Action] {
        var creators: [Tag: String] = [:]
        for tag in dataSet.tags where tag.isPrivate && (0x0010...0x00FF).contains(tag.element) {
            creators[tag] = dataSet.string(for: tag)?.trimmingCharacters(in: CharacterSet(charactersIn: " \u{0}"))
        }
        var actions: [Tag: ConfidentialityProfile.Action] = [:]
        var keptCreators = Set<Tag>()
        for tag in dataSet.tags where tag.isPrivate && tag.element >= 0x1000 {
            let creatorTag = Tag(group: tag.group, element: tag.element >> 8)
            guard let creator = creators[creatorTag], let element = dataSet[tag] else { continue }
            let low = tag.element & 0x00FF
            let key = String(format: "%04X|%02X", tag.group, low)
            let declaration = privateDeclarations[String(format: "%04X|", tag.group) + creator]
            let action: ConfidentialityProfile.Action?
            if ConfidentialityProfile.safePrivateAttributes["\(creator)|\(key)"] != nil
                || declaration?.status == "SAFE"
                || declaration?.nonidentifying.contains(low) == true {
                action = .keep
            } else if let code = declaration?.actions[low] {
                switch code {
                case "D": action = .replaceDummy
                case "Z": action = .zero
                case "U": action = element.vr == .UI ? .replaceUID : .replaceDummy
                default: action = nil  // X
                }
            } else if element.vr == .SQ || element.sequenceItems != nil {
                action = .keep
            } else {
                action = nil
            }
            if let action {
                actions[tag] = action
                keptCreators.insert(creatorTag)
            }
        }
        for creator in keptCreators { actions[creator] = .keep }
        return actions
    }

    /// VRs a Clean action can rewrite as text (PS3.5 Table 6.2-1 character VRs that may
    /// carry free text or names).
    static let cleanableVRs: Set<VR> = [.AE, .CS, .LO, .LT, .PN, .SH, .ST, .UC, .UT]
    /// Character VRs that are never multi-valued (PS3.5 Table 6.2-1).
    static let singleValuedVRs: Set<VR> = [.LT, .ST, .UT, .UR]
    static let binaryVRs: Set<VR> = [.OB, .OD, .OF, .OL, .OV, .OW, .UN, .US, .SS, .UL, .SL, .FL, .FD, .AT, .SV, .UV]

    /// The original values of every attribute the profile removes or replaces (X, Z, D,
    /// U and their combinations, and the PN / private sweeps), at any nesting depth.
    private func removedValues(in dataSet: DataSet, cleaning: Bool = false) -> [(String, VR)] {
        var out: [(String, VR)] = []
        let privateActions = options.retainSafePrivate ? safePrivateActions(in: dataSet) : [:]
        for tag in dataSet.tags {
            guard let element = dataSet[tag], tag != .pixelData, tag.group != 0x0002 else { continue }
            let effective = effectiveAction(for: tag, element: element, cleaning: cleaning,
                                            privateActions: privateActions)
            if let items = element.sequenceItems {
                let innerCleaning = cleaning || effective == .clean
                let contentItems = options.cleanStructuredContent && innerCleaning
                    && Self.contentItemSequences.contains(tag)
                let dummyContentItems = effective == .replaceDummy && Self.contentItemSequences.contains(tag)
                for item in items {
                    // Basic Profile D on Content Sequence: the values replaced (D236).
                    if dummyContentItems { out += Self.contentItemValues(in: item, recursive: false) }
                    // A Content Item the Clean Structured Content Option removes (X) takes its
                    // values, and those of its children, with it; a D replaces its own value.
                    switch contentItems ? ConfidentialityProfile.contentItemAction(for: item, options: options) : nil {
                    case .remove?, .removePreferred?:
                        out += Self.contentItemValues(in: item, recursive: true)
                        continue
                    case .replaceDummy?, .zero?, .zeroOrDummy?:
                        out += Self.contentItemValues(in: item, recursive: false)
                    default:
                        break
                    }
                    out += removedValues(in: DataSet(elements: item.allElements), cleaning: innerCleaning)
                }
                continue
            }
            guard let action = effective,
                  action != .keep, action != .clean,
                  Self.cleanableVRs.contains(element.vr) || [.DA, .DT, .AS, .UI].contains(element.vr),
                  let value = dataSet.string(for: tag) else { continue }
            let values = Self.singleValuedVRs.contains(element.vr) ? [value] : value.components(separatedBy: "\\")
            out += values.map { ($0, element.vr) }
        }
        return out
    }

    private func dummyValue(for vr: VR) -> String {
        Self.dummyString(for: vr)
    }

    private static func dummyString(for vr: VR) -> String {
        switch vr {
        case .PN: return "ANONYMOUS"
        case .DA: return "19000101"
        case .TM: return "000000"
        case .DT: return "19000101000000"
        case .AS: return "000D"
        case .IS, .DS: return "0"
        default:  return "ANONYMIZED"
        }
    }

    /// Z: a zero-length value — an empty sequence for SQ (PS3.15 E.1.1).
    private static func setZeroLength(_ tag: Tag, vr: VR, in dataSet: inout DataSet) {
        if vr == .SQ {
            dataSet.setSequence([], for: tag)
        } else {
            dataSet.setString("", for: tag, vr: vr)
        }
    }

    /// One value's worth of zero bytes for a binary VR (even length).
    private static func binaryDummyLength(_ vr: VR) -> Int {
        switch vr {
        case .FD, .OD, .SV, .UV, .OV: return 8
        case .UL, .SL, .FL, .OF, .OL, .AT: return 4
        default: return 2
        }
    }

    private mutating func mappedUID(_ uid: String) -> String {
        if let existing = uidMap[uid] { return existing }
        let generated = UIDGenerator.generateUID().value
        uidMap[uid] = generated
        return generated
    }

    static func shiftDICOMDate(_ dicom: String, byDays days: Int) -> String? {
        let utc = TimeZone(identifier: "UTC")!
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = utc  // whole days in UTC: no daylight-saving hour can move the date
        let f = DateFormatter()
        f.calendar = calendar
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyyMMdd"
        f.timeZone = utc
        let trimmed = dicom.trimmingCharacters(in: .whitespaces)
        guard trimmed.count == 8, trimmed.allSatisfy(\.isASCII), trimmed.allSatisfy(\.isNumber),
              let date = f.date(from: trimmed),
              let shifted = calendar.date(byAdding: .day, value: days, to: date) else {
            return nil
        }
        return f.string(from: shifted)
    }

    /// Shifts the date part (YYYYMMDD) of a DT value by whole days, keeping the time and
    /// any UTC offset suffix (PS3.5 Table 6.2-1 DT). A DT with less than a full date
    /// (YYYY or YYYYMM) cannot be shifted by days: nil.
    static func shiftDICOMDateTime(_ dicom: String, byDays days: Int) -> String? {
        let trimmed = dicom.trimmingCharacters(in: .whitespaces)
        guard trimmed.count >= 8, let date = shiftDICOMDate(String(trimmed.prefix(8)), byDays: days) else {
            return nil
        }
        return date + trimmed.dropFirst(8)
    }

    // MARK: - Method recording (PS3.15 E.1.1 / PS3.3 C.7.1.1)

    /// PS3.15 E.1.1: "The Attribute Patient Identity Removed (0012,0062) shall be
    /// replaced or added to the Data Set with a value of YES. Additionally, one or more
    /// codes from PS3.16 CID 7050 corresponding to the Profile and Options used shall
    /// be added to De-identification Method Code Sequence (0012,0064), and/or a text
    /// string describing the method used shall be inserted in or added to
    /// De-identification Method (0012,0063)."
    ///
    /// PS3.3 Table C.7-1 makes (0012,0063) and (0012,0064) Type 1C when (0012,0062) is
    /// YES ("May be present otherwise"), so both are written in every case. VRs per
    /// PS3.6 Table 6-1: (0012,0062) CS, (0012,0063) LO VM 1-n, (0012,0064) SQ.
    private func recordMethod(in dataSet: inout DataSet, pixelsMayCarryPHI: Bool) {
        // (0012,0062) Patient Identity Removed. PS3.15 conditions YES on the whole
        // object being de-identified — pixels included. This engine only scrubs the
        // dataset, so when the pixels (or overlay planes) may still carry identifiers
        // we must not assert YES: a false YES is worse than no assertion, because
        // downstream consumers treat it as a release gate. Write NO instead, so the
        // state is explicit rather than merely absent.
        dataSet.setString(pixelsMayCarryPHI ? "NO" : "YES",
                          for: Self.patientIdentityRemovedTag, vr: .CS)

        // (0012,0064) De-identification Method Code Sequence: one Item per CID 7050
        // code for the profile and each option applied (Table C.7-1: "Multiple Items
        // are used … to describe options of a defined profile"). Items another pass
        // already recorded (e.g. 113101 from the pixel redactor) are kept, after the
        // profile's own Item (D160).
        let codes = options.methodCodes
        let existing = dataSet.sequence(for: Self.deidentificationMethodCodeSequence) ?? []
        let profileCode = ConfidentialityProfile.DeidentificationMethodCode.basicApplicationConfidentialityProfile
        func code(of item: SequenceItem) -> String? {
            item.string(for: .codeValue)?.trimmingCharacters(in: .whitespaces)
        }
        var items = [profileCode.sequenceItem]
        items += existing.filter { code(of: $0) != profileCode.codeValue }
        var recorded = Set(items.compactMap(code(of:)))
        for code in codes.dropFirst() where !recorded.contains(code.codeValue) {
            items.append(code.sequenceItem)
            recorded.insert(code.codeValue)
        }
        dataSet.setSequence(items, for: Self.deidentificationMethodCodeSequence)

        // (0012,0063) De-identification Method — LO, VM 1-n: one value per Item of
        // (0012,0064), in the same order (each Code Meaning is within the 64-character LO
        // limit), so an option recorded by another pass, such as Clean Pixel Data, is
        // named here too (D160).
        var method = ["PS3.15 Basic Application Level Confidentiality Profile"]
        method += items.dropFirst().compactMap { $0.string(for: .codeMeaning)?.trimmingCharacters(in: .whitespaces) }
        // Make the metadata-only scope explicit in the record itself, so a reader of the
        // file (not just of our console output) can see the pixels were never cleaned.
        if pixelsMayCarryPHI { method.append("DATASET ONLY - pixel data not de-identified") }
        dataSet.setStrings(method, for: Self.deidentificationMethod, vr: .LO)

        // (0028,0303) Longitudinal Temporal Information Modified, CS (PS3.3 Table C.7-1
        // Enumerated Values UNMODIFIED / MODIFIED / REMOVED): PS3.15 2026a E.2 "REMOVED"
        // if no Retain Longitudinal Temporal Information Option is applied; E.3.6
        // "UNMODIFIED" with Full Dates, "MODIFIED" with Modified Dates (D161).
        let temporal: String
        if !options.retainLongitudinalTemporal {
            temporal = "REMOVED"
        } else {
            temporal = options.dateOffsetDays == nil ? "UNMODIFIED" : "MODIFIED"
        }
        dataSet.setString(temporal, for: Self.longitudinalTemporalInformationModified, vr: .CS)

        // Burned In Annotation (0028,0301): we do not inspect pixels, so we cannot
        // assert NO. Leave any existing value; if absent, do not fabricate one.
        // When it says YES, the caller has already been warned and (0012,0062) is NO.
    }

    /// (0012,0062) Patient Identity Removed, CS.
    static let patientIdentityRemovedTag = Tag(group: 0x0012, element: 0x0062)
    /// (0012,0063) De-identification Method, LO VM 1-n.
    static let deidentificationMethod = Tag(group: 0x0012, element: 0x0063)
    /// (0012,0064) De-identification Method Code Sequence, SQ.
    static let deidentificationMethodCodeSequence = Tag(group: 0x0012, element: 0x0064)
    /// (0028,0303) Longitudinal Temporal Information Modified, CS.
    static let longitudinalTemporalInformationModified = Tag(group: 0x0028, element: 0x0303)
}

// MARK: - Clean ("C") action

/// Removes identifying information from a text value the profile keeps (PS3.15 2026a
/// Table E.1-1a "C"; E.3.5 Clean Descriptors Option: "any information that is embedded in
/// text or string Attributes corresponding to the Attribute information specified to be
/// removed by the Profile and any other Options specified shall also be removed").
///
/// The manner of cleaning (to be stated in a Conformance Statement, E.3.5):
/// 1. every value the profile removes or replaces in the same data set — each person
///    name component and the whole name, identifiers, addresses, institution and device
///    names, ages, UIDs, and dates (as YYYYMMDD, YYYY-MM-DD, YYYY.MM.DD, DD/MM/YYYY,
///    MM/DD/YYYY, DD.MM.YYYY) — is removed wherever it occurs as a whole word, ignoring
///    case;
/// 2. a capitalised word following a personal title (Dr, Mr, Mrs, Ms, Miss, Prof, case as
///    written) is removed with the title, since a person's name is information the profile removes even when it is
///    not elsewhere in the data set;
/// 3. the remaining text has its runs of spaces collapsed and is trimmed.
/// Values shorter than two characters are not used (they would remove ordinary letters).
struct DescriptorCleaner {
    private let patterns: [NSRegularExpression]

    init(values: [(String, VR)]) {
        var tokens = Set<String>()
        for (raw, vr) in values {
            let value = raw.trimmingCharacters(in: CharacterSet(charactersIn: " \u{0}"))
            guard !value.isEmpty else { continue }
            switch vr {
            case .PN:
                let components = value
                    .components(separatedBy: CharacterSet(charactersIn: "^="))
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                    .filter { !$0.isEmpty }
                tokens.formUnion(components)
                if components.count >= 2 {
                    tokens.insert(components.joined(separator: " "))
                    tokens.insert(components.reversed().joined(separator: " "))
                }
            case .DA, .DT:
                let digits = String(value.prefix(8))
                tokens.insert(value)
                if digits.count == 8, digits.allSatisfy(\.isNumber) {
                    let y = digits.prefix(4), m = digits.dropFirst(4).prefix(2), d = digits.suffix(2)
                    tokens.formUnion([digits, "\(y)-\(m)-\(d)", "\(y).\(m).\(d)",
                                      "\(d)/\(m)/\(y)", "\(m)/\(d)/\(y)", "\(d).\(m).\(y)"])
                }
            case .AS:
                tokens.insert(value)
                if let n = Int(value.prefix(3)) { tokens.insert("\(n)\(value.suffix(1))") }
            default:
                tokens.insert(value)
            }
        }
        var patterns: [NSRegularExpression] = []
        let boundary = "[\\p{L}\\p{N}]"
        // Longest first, so a whole name goes before its components.
        for token in tokens.filter({ $0.count >= 2 }).sorted(by: { $0.count > $1.count }) {
            let escaped = NSRegularExpression.escapedPattern(for: token)
            if let re = try? NSRegularExpression(
                pattern: "(?<!\(boundary))\(escaped)(?!\(boundary))", options: [.caseInsensitive]) {
                patterns.append(re)
            }
        }
        // Case-sensitive, and the name must be capitalised: "MR" and "MS" are modalities
        // and diagnoses, not titles.
        if let titles = try? NSRegularExpression(
            pattern: "(?<!\(boundary))(?:Dr|Mr|Mrs|Ms|Miss|Prof)\\.?\\s+\\p{Lu}[\\p{L}'\\-]*") {
            patterns.append(titles)
        }
        self.patterns = patterns
    }

    /// `text` with the identifying information removed.
    func clean(_ text: String) -> String {
        var out = text
        for re in patterns {
            out = re.stringByReplacingMatches(
                in: out, range: NSRange(out.startIndex..., in: out), withTemplate: "")
        }
        guard out != text else { return text }
        return out.replacingOccurrences(of: " {2,}", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
    }
}
